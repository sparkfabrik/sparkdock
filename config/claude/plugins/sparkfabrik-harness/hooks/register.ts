import type { EngineInterface, Register, ToolCallInput, ToolCallResult } from 'claude-code'
import { detectFormat, findCommits, hasIssueReference, isExempt, subjectProblem } from './commit-rules'
import {
  CREDENTIAL_DENY,
  destructiveReason,
  gitDirectory,
  hasCredentialUrl,
  isSecretPath,
  pushesCurrentBranch,
  readsDirectories,
  secretCandidates,
  secretDeny,
} from './guard-rules'
import { joinPath, parseCommands, type ShellCommand } from './shell'

// Skills the writing gate tracks; the Python classifier, shared with Codex,
// decides which of them a call requires.
const GATED_SKILLS = new Set(['gh', 'glab', 'sf-writing-style'])
const PLATFORM_CLI = /(^|[\s;&|(`/'"])(gh|glab)(\s|$)/
const PLATFORM_MCP = /slack|github|gitlab/i
const REMINDER =
  'Writing guard: this call was not blocked and its text was not evaluated. Apply ' +
  'sf-writing-style to each body you publish in this turn, including every ' +
  'task-specific reference it requires: lead with the change, use useful bullets, ' +
  'remove implementation history and repetition, and keep required actions.'

type Answer = 'yes' | 'no' | 'nobody'
type Loop = { loaded: Set<string>; requested: Set<string>; failed: Set<string>; warned: Set<string>; reminded: boolean }
type Next<E> = (e: E) => Promise<ToolCallResult>
type BashCall = ToolCallInput & { tool: 'Bash'; command: string }

// Skill state per model loop: '' is the main loop, otherwise a subagent id.
const loops = new Map<string, Loop>()

function loopOf(agentId: string | undefined): Loop {
  const key = agentId ?? ''
  let loop = loops.get(key)
  if (loop === undefined) {
    loop = { loaded: new Set(), requested: new Set(), failed: new Set(), warned: new Set(), reminded: false }
    loops.set(key, loop)
  }
  return loop
}

function isOff(value: string | undefined): boolean {
  return ['0', 'off', 'false', 'no'].includes((value ?? '').trim().toLowerCase())
}

function preview(text: string, limit: number): string {
  const flat = text.trim()
  return flat.length > limit ? `${flat.slice(0, limit)}…` : flat
}

function withContext(result: ToolCallResult, notes: string[]): ToolCallResult {
  return notes.length === 0 || result.deny !== undefined ? result : { ...result, context: [...(result.context ?? []), ...notes] }
}

function toolInput(e: ToolCallInput): Record<string, unknown> {
  const { tool: _tool, tool_use_id: _id, agentId: _agent, ...input } = e as ToolCallInput & Record<string, unknown>
  return input
}

// Asks in Claude Code's own dialog. `nobody` where no one can answer
// (`claude -p`, the SDK); a dismissed dialog counts as `no`.
async function confirm($: EngineInterface, question: string, header: string, proceed: string): Promise<Answer> {
  if ((await $.session.surfaces()).length === 0) {
    return 'nobody'
  }
  try {
    return (await $.ui.ask(question, { header, options: [proceed, 'Cancel'] })) === proceed ? 'yes' : 'no'
  } catch {
    return 'no'
  }
}

// Where a path points, relative to the session's directory; null when an
// earlier `cd` or a missing HOME makes it unknowable.
function locate(path: string, cwd: string | null | undefined, home: string | undefined): string | null {
  if (path === '~' || path.startsWith('~/')) {
    return home === undefined ? null : home + path.slice(1)
  }
  if (path.startsWith('/') || cwd === undefined) {
    return path
  }
  const base = cwd === null ? null : locate(cwd, undefined, home)
  return base === null ? null : joinPath(base, path)
}

// The directory a command runs in, `git -C` included.
function workdir(command: ShellCommand, home: string | undefined): string | null | undefined {
  const dir = gitDirectory(command.argv)
  if (dir !== undefined) {
    return locate(dir, command.cwd, home)
  }
  return command.cwd === undefined || command.cwd === null ? command.cwd : locate(command.cwd, undefined, home)
}

async function guardBash<E extends BashCall>($: EngineInterface, e: E, next: Next<E>): Promise<ToolCallResult> {
  if (hasCredentialUrl(e.command)) {
    return { deny: CREDENTIAL_DENY }
  }
  const commands = parseCommands(e.command)
  const home = await $.env.get('HOME')
  for (const command of commands) {
    for (const word of secretCandidates(command)) {
      const path = locate(word, command.cwd, home)
      // A path whose directory the shell decides is treated as present.
      if (path === null) {
        return { deny: secretDeny(word) }
      }
      const found = await $.fs.stat(path).catch(() => undefined)
      if (found?.kind === 'file' || (found?.kind === 'dir' && readsDirectories(command))) {
        return { deny: secretDeny(word) }
      }
    }
  }
  const reasons: string[] = []
  for (const command of commands) {
    let branch: string | undefined
    const cwd = pushesCurrentBranch(command) ? workdir(command, home) : null
    if (cwd !== null) {
      const ran = await $.process.run(['git', 'branch', '--show-current'], { cwd, timeoutMs: 5000 }).catch(() => undefined)
      branch = ran?.exitCode === 0 ? ran.stdout.trim() : undefined
    }
    const reason = destructiveReason(command, branch)
    if (reason !== undefined && !reasons.includes(reason)) {
      reasons.push(reason)
    }
  }
  if (reasons.length === 0) {
    return next(e)
  }
  const what = `This command ${reasons.join(', ')}`
  const answer = await confirm($, `${what}. Run it?\n\n${preview(e.command, 400)}`, 'Guard', 'Run it')
  if (answer === 'yes') {
    return next(e)
  }
  if (answer === 'nobody') {
    return { deny: `${what}, and nobody is here to confirm it. Ask the person to run it.` }
  }
  return { deny: `The person declined: ${what.toLowerCase()}. Do not retry it; ask how to proceed.` }
}

async function classify($: EngineInterface, e: ToolCallInput): Promise<{ required: string[]; available: string[] }> {
  // A classifier that cannot answer still leaves the call to the person.
  const unknown = { required: ['sf-writing-style'], available: [] }
  // The plugin lives at <sparkdock>/config/claude/plugins/sparkfabrik-harness.
  const script = `${$.plugin.root.replace(/\/+$/, '')}/../../../../sjust/scripts/claude-gh-gate.py`
  const payload = { tool_name: e.tool, tool_input: toolInput(e), cwd: await $.session.cwd() }
  const ran = await $.process.run(['python3', script, 'classify'], { stdin: JSON.stringify(payload), timeoutMs: 10000 }).catch(() => undefined)
  if (ran?.exitCode !== 0) {
    return unknown
  }
  try {
    const parsed = JSON.parse(ran.stdout) as { required?: unknown; available?: unknown }
    if (!Array.isArray(parsed.required)) {
      return unknown
    }
    const strings = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : [])
    return { required: strings(parsed.required), available: strings(parsed.available) }
  } catch {
    return unknown
  }
}

async function gateWriting<E extends ToolCallInput>($: EngineInterface, e: E, next: Next<E>): Promise<ToolCallResult> {
  const { required, available } = await classify($, e)
  if (required.length === 0) {
    return next(e)
  }
  const loop = loopOf(e.agentId)
  const notes: string[] = []
  const needed: string[] = []
  for (const name of required.filter(n => !loop.loaded.has(n))) {
    if (loop.failed.has(name) || loop.requested.has(name) || !available.includes(name)) {
      if (!loop.warned.has(name)) {
        loop.warned.add(name)
        notes.push(`Writing guard: skipping ${name}; unavailable or load not confirmed.`)
      }
      continue
    }
    needed.push(name)
  }
  if (needed.length > 0) {
    needed.forEach(name => loop.requested.add(name))
    return {
      deny:
        `Load these skills with the Skill tool: ${needed.join(', ')}. ` +
        'Read and apply any task-specific references required by those skills to the prepared text, then retry this command.',
    }
  }
  if (!required.includes('sf-writing-style')) {
    return withContext(await next(e), notes)
  }
  const text = e.tool === 'Bash' ? e.command : `${e.tool} ${JSON.stringify(toolInput(e), null, 1)}`
  const answer = await confirm($, `Publish this?\n\n${preview(text, 1500)}`, 'Publish', 'Publish')
  if (answer === 'no') {
    return { deny: 'The person did not publish this text. Ask what to change before trying again.' }
  }
  if (answer === 'nobody' && loop.loaded.has('sf-writing-style') && !loop.reminded) {
    loop.reminded = true
    notes.push(REMINDER)
  }
  return withContext(await next(e), notes)
}

async function gateCommit<E extends BashCall>($: EngineInterface, e: E, next: Next<E>): Promise<ToolCallResult> {
  const notes: string[] = []
  const home = await $.env.get('HOME')
  for (const { command, message } of findCommits(e.command)) {
    if ('skip' in message) {
      continue
    }
    const cwd = workdir(command, home)
    if (cwd === null) {
      continue
    }
    // Git reads a relative message file from the repository it commits in.
    const file = message.file === undefined ? undefined : locate(message.file, cwd, home)
    const fromFile =
      file === undefined ? '' : file === null ? undefined : await $.fs.read(file).then(t => (typeof t === 'string' ? t : undefined)).catch(() => undefined)
    if (fromFile === undefined) {
      continue
    }
    const text = [fromFile, ...message.parts].filter(Boolean).join('\n\n')
    const log = await $.process.run(['git', 'log', '--format=%s', '-n', '30'], { cwd, timeoutMs: 5000 }).catch(() => undefined)
    const format = detectFormat(log?.exitCode === 0 ? log.stdout.split('\n').filter(Boolean) : [])
    const subject = (text.split('\n')[0] ?? '').trim()
    const problem = subjectProblem(subject, format)
    if (problem !== undefined) {
      return { deny: problem }
    }
    if (isExempt(subject) || hasIssueReference(text, format)) {
      continue
    }
    const answer = await confirm($, `This commit has no Refs: or Closes: footer. Commit without an issue reference?\n\n${subject}`, 'Commit', 'Commit anyway')
    if (answer === 'no') {
      return { deny: 'The commit needs an issue reference. Ask the person for the issue and add a "Refs: owner/repo#N" or "Closes: owner/repo#N" trailer.' }
    }
    if (answer === 'nobody') {
      notes.push('Commit gate: this commit has no Refs: or Closes: footer. Mention the missing issue reference in your summary.')
    }
  }
  return withContext(await next(e), notes)
}

// Session ids that already carry the marker standing the Python settings hook down.
const marked = new Set<string>()

async function markerPath($: EngineInterface, id: string): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(id)))
  const hex = [...digest].map(b => b.toString(16).padStart(2, '0')).join('')
  const cache = (await $.env.get('XDG_CACHE_HOME')) || `${await $.env.get('HOME')}/.cache`
  return `${cache}/sparkdock/claude-skill-gate/mod-${hex}`
}

// The Python hook skips a session whose marker exists in its state directory.
async function markSession($: EngineInterface): Promise<void> {
  const id = await $.session.id()
  if (marked.has(id)) {
    return
  }
  await $.fs
    .write(await markerPath($, id), '')
    .then(() => marked.add(id))
    .catch(() => undefined)
}

// Hands the session back to the Python hook, for a resume without the mod.
async function unmarkSession($: EngineInterface): Promise<void> {
  const id = await $.session.id()
  marked.delete(id)
  await $.process.run(['rm', '-f', await markerPath($, id)], { timeoutMs: 5000 }).catch(() => undefined)
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await markSession($)
    return next(e)
  })

  on('session.end', async ($, e, next) => {
    loops.clear()
    await unmarkSession($)
    return next(e)
  })

  on('session.compact', async ($, e, next) => {
    const result = await next(e)
    loops.delete(e.agentId ?? '')
    return result
  })

  on('prompt.submit', async ($, e, next) => {
    // A /clear starts a new session id with no session.start.
    await markSession($)
    loopOf(undefined).reminded = false
    return next(e)
  })

  on('tool.call', { tool: 'Skill' }, async ($, e, next) => {
    const result = await next(e)
    if (GATED_SKILLS.has(e.skill)) {
      const loop = loopOf(e.agentId)
      if (result.deny === undefined && result.isError !== true) {
        loop.loaded.add(e.skill)
        loop.failed.delete(e.skill)
      } else {
        loop.failed.add(e.skill)
      }
    }
    return result
  })

  // Command guard (#658).
  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    return isOff(await $.env.get('SPARKDOCK_COMMAND_GUARD')) ? next(e) : guardBash($, e, next)
  })

  on('tool.call', { tool: ['Read', 'Edit', 'Write', 'WebFetch'] }, async ($, e, next) => {
    if (isOff(await $.env.get('SPARKDOCK_COMMAND_GUARD'))) {
      return next(e)
    }
    if (e.tool === 'WebFetch') {
      return hasCredentialUrl(e.url) ? { deny: CREDENTIAL_DENY } : next(e)
    }
    return isSecretPath(e.file_path) ? { deny: secretDeny(e.file_path) } : next(e)
  })

  // Builds that ship a Grep tool; its input is not in every build's types.
  on('tool.call', { tool: /^Grep$/ }, async ($, e, next) => {
    const { path, glob } = toolInput(e)
    const secret = [path, glob].find((p): p is string => typeof p === 'string' && isSecretPath(p))
    return secret === undefined || isOff(await $.env.get('SPARKDOCK_COMMAND_GUARD')) ? next(e) : { deny: secretDeny(secret) }
  })

  // Writing gate (#659).
  on('tool.call', { tool: /^(?:Bash|mcp__.*)$/ }, async ($, e, next) => {
    const platform = e.tool === 'Bash' ? PLATFORM_CLI.test(e.command) : e.tool.startsWith('mcp__') && PLATFORM_MCP.test(e.tool)
    return !platform || isOff(await $.env.get('SPARKDOCK_GH_GATE')) ? next(e) : gateWriting($, e, next)
  })

  // Commit gate (#660).
  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    return !/\bcommit\b/.test(e.command) || isOff(await $.env.get('SPARKDOCK_COMMIT_GATE')) ? next(e) : gateCommit($, e, next)
  })

  on('attribution.text', { kind: 'commit' }, async ($, e, next) => {
    return isOff(await $.env.get('SPARKDOCK_COMMIT_GATE')) ? next(e) : { text: `Assisted-by: claude-code/${await $.session.model()}` }
  })
}
