import { basename, hasFlag, subcommand, type ShellCommand } from './shell'

// Credentials embedded in a URL: `user:secret@`, a token variable or a known
// token prefix before `@`. Plain HTTPS and `git@host` SSH URLs do not match.
const CREDENTIAL_URL = [
  /\b(?:https?|git|ssh):\/\/[^\s/@:'"]+:[^\s/@'"]+@/i,
  /\b(?:https?|git|ssh):\/\/\$\{?\w*(?:TOKEN|PAT|PASS|SECRET)\w*\}?@/i,
  /\b(?:https?|git|ssh):\/\/(?:ghp_|gho_|ghs_|github_pat_|glpat-)[^\s@]*@/,
]

export const CREDENTIAL_DENY =
  'Credentials in a URL end up in shell history, .git/config and remote logs. ' +
  'Use an SSH remote (git@host:group/project.git) or a credential helper, and keep tokens out of URLs.'

const ENV_TEMPLATE = /^\.env\.(?:example|sample|template|dist)$/
const NON_READING = new Set(['ls', 'stat', 'test', '['])
// Commands that read the files beneath a directory operand.
const DIRECTORY_READERS = new Set(['grep', 'egrep', 'fgrep', 'rg', 'ag', 'ack', 'find', 'tar', 'zip', 'cp', 'rsync', 'scp', 'tree'])
const GIT_VALUED = new Set(['-C', '-c'])
const PUSH_VALUED = new Set(['--repo', '-o', '--push-option', '--receive-pack', '--exec'])
const KUBECTL_VALUED = new Set(['-n', '--namespace', '--context', '--kubeconfig', '--cluster', '--user', '-s', '--server'])
const DOCKER_VALUED = new Set(['--context', '-H', '--host', '--config'])
const PROTECTED_BRANCHES = new Set(['main', 'master'])

export function hasCredentialUrl(text: string): boolean {
  return CREDENTIAL_URL.some(pattern => pattern.test(text))
}

// The org policy's secret files; env templates stay readable.
export function isSecretPath(path: string): boolean {
  const parts = path.split('/')
  const name = parts.pop() ?? ''
  if (ENV_TEMPLATE.test(name)) {
    return false
  }
  return (
    name === '.env' ||
    name === '.env.local' ||
    /^\.env\..+\.local$/.test(name) ||
    /^\.env\.(?:development|production|staging|test)$/.test(name) ||
    parts.includes('secrets') ||
    name.includes('credentials') ||
    name.includes('secret') ||
    name.endsWith('.pem') ||
    name.endsWith('.key')
  )
}

export function secretDeny(path: string): string {
  return `${path} is a secret file under SparkFabrik policy: do not read or edit it. Ask the person to handle it, or use a template such as .env.example.`
}

// Arguments and redirection targets that may name a secret file the command
// reads or writes; the caller checks which of them exist.
export function secretCandidates(command: ShellCommand): string[] {
  const operands = NON_READING.has(basename(command.argv[0] ?? '')) ? [] : command.argv.slice(1)
  return [...operands, ...command.redirects].filter(word => !word.startsWith('-') && !word.includes('$') && isSecretPath(word))
}

// True when the command reads the contents of a directory operand.
export function readsDirectories(command: ShellCommand): boolean {
  return DIRECTORY_READERS.has(basename(command.argv[0] ?? ''))
}

function pushRefspecs(args: string[]): string[] {
  const positional: string[] = []
  for (let i = 0; i < args.length; i++) {
    const arg = args[i] ?? ''
    if (PUSH_VALUED.has(arg)) {
      i++
    } else if (!arg.startsWith('-')) {
      positional.push(arg)
    }
  }
  return positional.slice(1)
}

function branchOf(refspec: string): string {
  const destination = refspec.includes(':') ? refspec.slice(refspec.lastIndexOf(':') + 1) : refspec
  return destination.replace(/^\+/, '').replace(/^refs\/heads\//, '')
}

// The `-C` directory of a git command, for commands the guard runs beside it.
export function gitDirectory(argv: string[]): string | undefined {
  const at = argv.indexOf('-C')
  return at !== -1 ? argv[at + 1] : undefined
}

// True for a `git push` whose target branch is the current one.
export function pushesCurrentBranch(command: ShellCommand): boolean {
  const { argv } = command
  if (basename(argv[0] ?? '') !== 'git') {
    return false
  }
  const sub = subcommand(argv, GIT_VALUED)
  if (sub?.name !== 'push') {
    return false
  }
  const refspecs = pushRefspecs(sub.args)
  return refspecs.length === 0 || refspecs.some(r => branchOf(r) === 'HEAD')
}

// Why a command needs the person's confirmation, or undefined when it does not.
// `branch` is the current branch, for a push that targets it; undefined when
// it could not be determined.
export function destructiveReason(command: ShellCommand, branch: string | undefined): string | undefined {
  const { argv } = command
  const name = basename(argv[0] ?? '')
  if (command.isSudo) {
    return 'runs as root with sudo'
  }
  if (name === 'rm' && (hasFlag(argv.slice(1), 'r', '--recursive') || hasFlag(argv.slice(1), 'R'))) {
    return 'deletes recursively'
  }
  if (name === 'git') {
    const sub = subcommand(argv, GIT_VALUED)
    if (sub === null) {
      return undefined
    }
    const { args } = sub
    if (sub.name === 'reset' && args.includes('--hard')) {
      return 'discards local changes (git reset --hard)'
    }
    if (sub.name === 'clean' && hasFlag(args, 'f', '--force')) {
      return 'deletes untracked files (git clean -f)'
    }
    if (sub.name === 'branch' && (hasFlag(args, 'D') || (args.includes('--delete') && args.includes('--force')))) {
      return 'force-deletes a branch (git branch -D)'
    }
    if (sub.name === 'push') {
      const refspecs = pushRefspecs(args)
      if (
        hasFlag(args, 'f', '--force') ||
        args.some(a => a.startsWith('--force-with-lease') || a === '--force-if-includes') ||
        refspecs.some(r => r.startsWith('+'))
      ) {
        return 'force-pushes'
      }
      if (args.includes('--all') || args.includes('--mirror')) {
        return 'pushes every branch, main or master included'
      }
      if (branch === undefined && pushesCurrentBranch(command)) {
        return 'pushes the current branch, which could not be determined'
      }
      const branches = refspecs.map(branchOf).map(b => (b === 'HEAD' ? (branch ?? '') : b))
      if (refspecs.length === 0) {
        branches.push(branch ?? '')
      }
      const hit = branches.find(b => PROTECTED_BRANCHES.has(b))
      return hit === undefined ? undefined : `pushes to ${hit}`
    }
    return undefined
  }
  if (name === 'terraform' || name === 'tofu') {
    const sub = subcommand(argv, new Set())
    if (sub !== null && (sub.name === 'apply' || sub.name === 'destroy')) {
      return `changes infrastructure (${name} ${sub.name})`
    }
  }
  if (name === 'kubectl') {
    const sub = subcommand(argv, KUBECTL_VALUED)
    if (sub !== null && (sub.name === 'delete' || sub.name === 'drain')) {
      return `changes the cluster (kubectl ${sub.name})`
    }
  }
  if (name === 'docker') {
    const sub = subcommand(argv, DOCKER_VALUED)
    if (sub?.name === 'system' && sub.args[0] === 'prune') {
      return 'prunes Docker data (docker system prune)'
    }
    if (sub?.name === 'volume' && (sub.args[0] === 'rm' || sub.args[0] === 'prune')) {
      return `removes Docker volumes (docker volume ${sub.args[0]})`
    }
    if (sub?.name === 'rm' && hasFlag(sub.args, 'f', '--force')) {
      return 'force-removes containers (docker rm -f)'
    }
  }
  return undefined
}
