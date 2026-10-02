import type { On } from 'claude-code'
import { describe, expect, mock, test } from 'claude-code/testing'

type World = { env?: Record<string, string>; surfaces?: string[]; answer?: string; files?: string[]; branch?: string; subjects?: string[]; classify?: object }

// Stands in for the engine beneath the plugin, and records what reached the tools.
function world(on: On, w: World): { ran: string[]; asked: string[] } {
  const ran: string[] = []
  const asked: string[] = []
  mock.env(on, { HOME: '/home/probe', ...w.env })
  on('session.surfaces', async () => ({ value: w.surfaces ?? ['terminal'] }) as never)
  on('session.cwd', async () => ({ value: '/work' }))
  on('session.model', async () => ({ value: 'claude-opus-5-5' }))
  // `$.ui.ask` reaches the engine as an AskUserQuestion tool call.
  on('tool.call', { tool: 'AskUserQuestion' }, async ($, e) => {
    const question = e.questions[0]?.question ?? ''
    asked.push(question)
    return { result: { questions: e.questions, answers: { [question]: w.answer ?? 'Cancel' } } } as never
  })
  on('fs.stat', async ($, e) => {
    // The engine may hand the path over resolved against the session's directory.
    if (!(w.files ?? []).some(f => e.path === f || e.path.endsWith(`/${f}`))) {
      return { deny: 'ENOENT' }
    }
    return { value: { kind: 'file', size: 1, mtimeMs: 0, isLink: false } }
  })
  on('process.run', async ($, e) => {
    const argv = (e as { argv: string[] }).argv
    const stdout =
      argv[1] === 'branch' ? `${w.branch ?? 'feat/x'}\n` : argv[1] === 'log' ? (w.subjects ?? ['feat: a', 'fix: b']).join('\n') : JSON.stringify(w.classify ?? { required: [], available: [] })
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } } as never
  })
  on('tool.call', async ($, e) => {
    ran.push(e.tool === 'Bash' ? e.command : e.tool)
    return { result: 'ok' } as never
  })
  return { ran, asked }
}

// What the model reads when a hook refuses the call.
const refusal = (out: { deny?: string; text?: string }) => String(out.deny ?? out.text)

const bash = (command: string) => ({ tool: 'Bash', tool_use_id: 'toolu_1', command }) as const

describe('command guard', () => {
  test('denies credentials in URLs without asking', async ($, on) => {
    const { ran, asked } = world(on, {})
    const out = await $.tool.call(bash('git clone https://probe:secret@example.invalid/x.git'))
    expect(refusal(out)).toMatch(/Credentials in a URL/)
    expect(ran).toEqual([])
    expect(asked).toEqual([])
  })

  test('lets a plain HTTPS clone through', async ($, on) => {
    const { ran } = world(on, {})
    await $.tool.call(bash('git clone https://gitlab.sparkfabrik.com/g/p.git'))
    expect(ran).toEqual(['git clone https://gitlab.sparkfabrik.com/g/p.git'])
  })

  test('denies reading an existing secret file', async ($, on) => {
    const { ran } = world(on, { files: ['.env'] })
    const out = await $.tool.call(bash('cat .env'))
    expect(refusal(out)).toMatch(/secret file/)
    expect(ran).toEqual([])
  })

  test('denies the Read tool on a secret path', async ($, on) => {
    const { ran } = world(on, {})
    const out = await $.tool.call({ tool: 'Read', tool_use_id: 'toolu_2', file_path: '/work/certs/tls.pem' } as never)
    expect(refusal(out)).toMatch(/secret file/)
    expect(ran).toEqual([])
  })

  test('asks before rm -rf and runs it when confirmed', async ($, on) => {
    const { ran, asked } = world(on, { answer: 'Run it' })
    await $.tool.call(bash('rm -rf build'))
    expect(asked.length).toBe(1)
    expect(asked[0]).toMatch(/deletes recursively/)
    expect(ran).toEqual(['rm -rf build'])
  })

  test('denies a declined push to master', async ($, on) => {
    const { ran } = world(on, { answer: 'Cancel', branch: 'master' })
    const out = await $.tool.call(bash('git push'))
    expect(refusal(out)).toMatch(/declined: this command pushes to master/)
    expect(ran).toEqual([])
  })

  test('denies a destructive command when nobody can answer', async ($, on) => {
    const { ran, asked } = world(on, { surfaces: [] })
    const out = await $.tool.call(bash('terraform destroy'))
    expect(refusal(out)).toMatch(/nobody is here to confirm/)
    expect(asked).toEqual([])
    expect(ran).toEqual([])
  })

  test('stays out of the way when disabled', async ($, on) => {
    const { ran } = world(on, { env: { SPARKDOCK_COMMAND_GUARD: '0' } })
    await $.tool.call(bash('cat .env'))
    expect(ran).toEqual(['cat .env'])
  })
})

describe('writing gate', () => {
  const publish = { required: ['gh', 'sf-writing-style'], available: ['gh', 'sf-writing-style'] }

  test('asks for missing skills once, then lets the retry through', async ($, on) => {
    const { ran } = world(on, { classify: publish, surfaces: [] })
    const first = await $.tool.call(bash('gh pr create --title t --body b'))
    expect(refusal(first)).toMatch(/Load these skills with the Skill tool: gh, sf-writing-style/)
    await $.tool.call(bash('gh pr create --title t --body b'))
    expect(ran).toEqual(['gh pr create --title t --body b'])
  })

  test('shows the text and publishes only when confirmed', async ($, on) => {
    const { ran, asked } = world(on, { classify: publish, answer: 'Cancel' })
    await $.tool.call({ tool: 'Skill', tool_use_id: 'toolu_3', skill: 'gh' } as never)
    await $.tool.call({ tool: 'Skill', tool_use_id: 'toolu_4', skill: 'sf-writing-style' } as never)
    const out = await $.tool.call(bash('gh pr create --title t --body b'))
    expect(asked[0]).toMatch(/Publish this\?[\s\S]*gh pr create/)
    expect(refusal(out)).toMatch(/did not publish/)
    expect(ran).toEqual(['Skill', 'Skill'])
  })
})

describe('commit gate', () => {
  test('denies a subject outside the repository format', async ($, on) => {
    const { ran } = world(on, {})
    const out = await $.tool.call(bash("git commit -m 'Add the file'"))
    expect(refusal(out)).toMatch(/conventional commit subjects/)
    expect(ran).toEqual([])
  })

  test('asks about a missing issue footer', async ($, on) => {
    const { ran, asked } = world(on, { answer: 'Commit anyway' })
    await $.tool.call(bash("git commit -m 'feat: add the file'"))
    expect(asked[0]).toMatch(/no Refs: or Closes: footer/)
    expect(ran).toEqual(["git commit -m 'feat: add the file'"])
  })

  test('commits with a footer without asking', async ($, on) => {
    const { asked } = world(on, {})
    await $.tool.call(bash("git commit -m 'feat: add the file' -m 'Refs: o/r#1'"))
    expect(asked).toEqual([])
  })

  test('rewrites commit attribution to the Assisted-by trailer', async ($, on) => {
    world(on, {})
    on('attribution.text', async ($, e) => ({ text: e.text }))
    const out = await $.attribution.text({ kind: 'commit', text: 'Co-Authored-By: Claude' })
    expect(out.text).toBe('Assisted-by: claude-code/claude-opus-5-5')
  })
})
