import { basename, parseCommands, subcommand } from './shell'

const CONVENTIONAL = /^(?:feat|fix|chore|test|docs|refactor|style|perf|ci|build|revert)(?:\([^)\s]+\))?!?: \S/
const LEGACY = /^refs #\d+: \S/
const JIRA = /^(?:\[[A-Z][A-Z0-9]+-\d+\] |[A-Z][A-Z0-9]+-\d+: )\S/
const EXEMPT = /^(?:Merge |Revert "|fixup! |squash! |amend! )/
const ISSUE_FOOTER = /^(?:Refs|Closes|Fixes|Resolves):\s*\S/im
const MAX_SUBJECT = 72
const GIT_VALUED = new Set(['-C', '-c'])
// `git commit` options that take the next word as their value.
const COMMIT_VALUED = new Set(['--author', '--date', '-t', '--template', '--cleanup', '--pathspec-from-file'])
const REUSE = new Set(['-C', '-c', '--reuse-message', '--reedit-message', '--fixup', '--squash'])
const HEREDOC = /^\$\(\s*cat\s+<<-?\s*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\1[^\n]*\n([\s\S]*?)\n[ \t]*\2[ \t]*\n?\s*\)$/

export type Format = 'conventional' | 'legacy' | 'jira'

const FORMATS: { format: Format; pattern: RegExp; example: string }[] = [
  { format: 'conventional', pattern: CONVENTIONAL, example: 'feat(scope): add the thing' },
  { format: 'legacy', pattern: LEGACY, example: 'refs #42: add the thing' },
  { format: 'jira', pattern: JIRA, example: 'ACME-42: add the thing' },
]

// What git would use as the message. `file` asks the caller to read it.
export type CommitMessage = { parts: string[]; file?: string } | { skip: 'dynamic' | 'editor' | 'reuse' }

export type Commit = { argv: string[]; message: CommitMessage }

// A message part as git receives it, or undefined when the shell computes it.
function literal(value: string): string | undefined {
  const heredoc = HEREDOC.exec(value)
  if (heredoc) {
    return heredoc[3]
  }
  return value.includes('$(') || value.includes('`') || /\$\{?[A-Za-z_]/.test(value) ? undefined : value
}

export function commitMessage(args: string[]): CommitMessage {
  const parts: string[] = []
  const trailers: string[] = []
  let file: string | undefined
  for (let i = 0; i < args.length; i++) {
    const arg = args[i] ?? ''
    const eq = arg.indexOf('=')
    const [flag, inline]: [string, string | undefined] =
      arg.startsWith('--') && eq !== -1
        ? [arg.slice(0, eq), arg.slice(eq + 1)]
        : /^-[A-Za-z]*m$/.test(arg)
          ? ['-m', undefined]
          : arg.startsWith('-m') && arg.length > 2
            ? ['-m', arg.slice(2)]
            : [arg, undefined]
    const value = () => inline ?? args[++i] ?? ''
    if (flag === '-m' || flag === '--message' || flag === '--trailer') {
      const text = literal(value())
      if (text === undefined) {
        return { skip: 'dynamic' }
      }
      if (flag === '--trailer') {
        trailers.push(text.replace(/^([^:=]+)=/, '$1: '))
      } else {
        parts.push(text.replace(/\s+$/, ''))
      }
    } else if (flag === '-F' || flag === '--file') {
      file = value()
      if (file === '-' || literal(file) === undefined) {
        return { skip: 'dynamic' }
      }
    } else if (REUSE.has(flag)) {
      return { skip: 'reuse' }
    } else if (COMMIT_VALUED.has(flag) && inline === undefined) {
      i++
    }
  }
  if (parts.length === 0 && file === undefined) {
    return { skip: 'editor' }
  }
  return { parts: trailers.length > 0 ? [...parts, trailers.join('\n')] : parts, file }
}

export function findCommits(command: string): Commit[] {
  const commits: Commit[] = []
  for (const { argv } of parseCommands(command)) {
    if (basename(argv[0] ?? '') !== 'git') {
      continue
    }
    const sub = subcommand(argv, GIT_VALUED)
    if (sub?.name === 'commit') {
      commits.push({ argv, message: commitMessage(sub.args) })
    }
  }
  return commits
}

// The format most recent subjects follow; the newest decides a tie.
export function detectFormat(subjects: string[]): Format | undefined {
  const counts = new Map<Format, number>()
  let newest: Format | undefined
  for (const subject of subjects) {
    if (EXEMPT.test(subject)) {
      continue
    }
    const match = FORMATS.find(f => f.pattern.test(subject))
    if (match !== undefined) {
      newest ??= match.format
      counts.set(match.format, (counts.get(match.format) ?? 0) + 1)
    }
  }
  const top = Math.max(0, ...counts.values())
  if (top === 0) {
    return undefined
  }
  const leaders = [...counts].filter(([, n]) => n === top).map(([f]) => f)
  return leaders.length === 1 ? leaders[0] : newest
}

export function isExempt(subject: string): boolean {
  return EXEMPT.test(subject)
}

export function subjectProblem(subject: string, format: Format | undefined): string | undefined {
  if (EXEMPT.test(subject)) {
    return undefined
  }
  if (subject.length > MAX_SUBJECT) {
    return `The commit subject is ${subject.length} characters; keep it under ${MAX_SUBJECT} and move detail into the body.`
  }
  const rule = FORMATS.find(f => f.format === format)
  if (rule !== undefined && !rule.pattern.test(subject)) {
    return `This repository uses ${rule.format} commit subjects, such as "${rule.example}". Load sf-commit-convention and rewrite the subject.`
  }
  return undefined
}

export function hasIssueReference(message: string, format: Format | undefined): boolean {
  return ISSUE_FOOTER.test(message) || (format === 'legacy' && LEGACY.test(message))
}
