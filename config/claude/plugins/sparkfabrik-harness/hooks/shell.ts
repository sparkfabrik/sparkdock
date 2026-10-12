// Best-effort reading of a Bash command into argv lists, without running it.
// Quotes, escapes, separators, command substitutions, heredocs and the
// wrappers Claude commonly adds are understood; anything else stays literal.

const WRAPPERS = new Set(['command', 'builtin', 'exec', 'nohup', 'time', 'nice', 'env', 'timeout'])
// Wrapper options that take the next word as their value.
const WRAPPER_VALUED: Record<string, ReadonlySet<string>> = {
  env: new Set(['-u', '--unset', '-C', '--chdir']),
  nice: new Set(['-n', '--adjustment']),
  time: new Set(['-f', '--format', '-o', '--output']),
  exec: new Set(['-a']),
  timeout: new Set(['-s', '--signal', '-k', '--kill-after']),
}
const SHELLS = new Set(['bash', 'sh', 'zsh', 'dash'])
const MAX_DEPTH = 4

export type ShellCommand = {
  argv: string[]
  // Raw text of each word, quotes and substitutions kept.
  raw: string[]
  // True when `sudo` wrapped the command.
  isSudo: boolean
  // Targets of `<` and `>` redirections.
  redirects: string[]
  // Directory set by an earlier `cd` in the same command line, relative to the
  // session's; undefined when none ran, null when the shell decides it.
  cwd: string | null | undefined
}

type Word = { value: string; raw: string }
type Lexed = { words: Word[]; redirects: string[] }

export function basename(path: string): string {
  return path.replace(/\/+$/, '').split('/').pop() ?? path
}

function closingParen(text: string, start: number): number {
  let depth = 1
  for (let i = start; i < text.length; i++) {
    const c = text[i]
    if (c === '\\') {
      i++
    } else if (c === "'") {
      const end = text.indexOf("'", i + 1)
      i = end === -1 ? text.length : end
    } else if (c === '<' && text[i + 1] === '<') {
      const match = /^<<-?[ \t]*(['"]?)([^\s'"<>;&|()]+)\1[^\n]*\n/.exec(text.slice(i))
      if (match) {
        i = heredocEnd(text, i + match[0].length, match[2] ?? '')
      }
    } else if (c === '(') {
      depth++
    } else if (c === ')' && --depth === 0) {
      return i
    }
  }
  return text.length
}

// Index of the newline ending a heredoc's delimiter line; the body is opaque.
function heredocEnd(text: string, bodyStart: number, delimiter: string): number {
  let lineStart = bodyStart
  while (lineStart < text.length) {
    const lineEnd = text.indexOf('\n', lineStart)
    const stop = lineEnd === -1 ? text.length : lineEnd
    if (text.slice(lineStart, stop).replace(/^\t+/, '').trimEnd() === delimiter) {
      return stop
    }
    lineStart = stop + 1
  }
  return text.length
}

// Command substitutions in an unquoted heredoc body, which the shell expands.
function bodySubstitutions(body: string, substitutions: string[]): void {
  for (let i = 0; i < body.length; i++) {
    if (body[i] === '\\') {
      i++
    } else if (body[i] === '$' && body[i + 1] === '(') {
      const end = closingParen(body, i + 2)
      substitutions.push(body.slice(i + 2, end))
      i = end
    } else if (body[i] === '`') {
      const end = body.indexOf('`', i + 1)
      const stop = end === -1 ? body.length : end
      substitutions.push(body.slice(i + 1, stop))
      i = stop
    }
  }
}

// Splits `text` into commands of words. Substitution bodies are collected so
// the caller can read the commands inside them too.
function lex(text: string, substitutions: string[]): Lexed[] {
  const commands: Lexed[] = []
  let words: Word[] = []
  let redirects: string[] = []
  let value = ''
  let raw = ''
  let inWord = false
  let skipNext = false
  const heredocs: { delimiter: string; quoted: boolean }[] = []

  const endWord = () => {
    if (inWord) {
      if (skipNext) {
        skipNext = false
        redirects.push(value)
      } else {
        words.push({ value, raw })
      }
    }
    value = ''
    raw = ''
    inWord = false
  }
  const endCommand = () => {
    endWord()
    if (words.length > 0 || redirects.length > 0) {
      commands.push({ words, redirects })
    }
    words = []
    redirects = []
  }

  for (let i = 0; i < text.length; i++) {
    const c = text[i]
    if (c === '\n' && heredocs.length > 0) {
      endCommand()
      // Heredoc bodies are data, but an unquoted delimiter lets the shell
      // run the substitutions inside.
      for (const { delimiter, quoted } of heredocs.splice(0)) {
        const start = i + 1
        i = heredocEnd(text, start, delimiter)
        if (!quoted) {
          bodySubstitutions(text.slice(start, i), substitutions)
        }
      }
      continue
    }
    if (c === ' ' || c === '\t' || c === '\r') {
      endWord()
    } else if (c === '\n' || c === ';' || c === '|' || c === '&' || c === '(' || c === ')') {
      endCommand()
    } else if (c === '#' && !inWord) {
      const end = text.indexOf('\n', i)
      i = (end === -1 ? text.length : end) - 1
    } else if (c === '<' || c === '>') {
      // Digits right before a redirection name a file descriptor, as in `2>&1`.
      if (inWord && /^\d+$/.test(raw)) {
        value = ''
        raw = ''
        inWord = false
      }
      endWord()
      if (c === '<' && text[i + 1] === '<' && text[i + 2] !== '<') {
        let j = i + 2
        if (text[j] === '-') {
          j++
        }
        while (text[j] === ' ' || text[j] === '\t') {
          j++
        }
        const match = /^(['"]?)([^\s'"<>;&|()]+)\1/.exec(text.slice(j))
        if (match) {
          heredocs.push({ delimiter: match[2] ?? '', quoted: match[1] !== '' })
          i = j + match[0].length - 1
          continue
        }
      }
      while (text[i + 1] === '<' || text[i + 1] === '>' || text[i + 1] === '&') {
        i++
      }
      // A redirect's target is not an argument of the command.
      skipNext = true
    } else if (c === '\\') {
      if (text[i + 1] === '\n') {
        i++
        continue
      }
      inWord = true
      value += text[i + 1] ?? ''
      raw += text.slice(i, i + 2)
      i++
    } else if (c === "'") {
      const end = text.indexOf("'", i + 1)
      const stop = end === -1 ? text.length : end
      inWord = true
      value += text.slice(i + 1, stop)
      raw += text.slice(i, stop + 1)
      i = stop
    } else if (c === '"') {
      inWord = true
      raw += c
      let j = i + 1
      for (; j < text.length && text[j] !== '"'; j++) {
        if (text[j] === '\\' && '"\\$`\n'.includes(text[j + 1] ?? '')) {
          value += text[j + 1]
          raw += text.slice(j, j + 2)
          j++
        } else if (text[j] === '$' && text[j + 1] === '(') {
          const end = closingParen(text, j + 2)
          substitutions.push(text.slice(j + 2, end))
          value += text.slice(j, end + 1)
          raw += text.slice(j, end + 1)
          j = end
        } else if (text[j] === '`') {
          const end = text.indexOf('`', j + 1)
          const stop = end === -1 ? text.length : end
          substitutions.push(text.slice(j + 1, stop))
          value += text.slice(j, stop + 1)
          raw += text.slice(j, stop + 1)
          j = stop
        } else {
          value += text[j]
          raw += text[j]
        }
      }
      raw += '"'
      i = j
    } else if (c === '$' && text[i + 1] === '(') {
      const end = closingParen(text, i + 2)
      substitutions.push(text.slice(i + 2, end))
      inWord = true
      value += text.slice(i, end + 1)
      raw += text.slice(i, end + 1)
      i = end
    } else if (c === '`') {
      const end = text.indexOf('`', i + 1)
      const stop = end === -1 ? text.length : end
      substitutions.push(text.slice(i + 1, stop))
      inWord = true
      value += text.slice(i, stop + 1)
      raw += text.slice(i, stop + 1)
      i = stop
    } else {
      inWord = true
      value += c
      raw += c
    }
  }
  endCommand()
  return commands
}

// The command string of `bash -c`, `bash -lc` or `bash -e -o pipefail -c`.
function shellScript(words: Word[]): string | undefined {
  let hasC = false
  let i = 1
  for (; i < words.length && /^[-+]/.test(words[i]?.value ?? ''); i++) {
    const option = words[i]?.value ?? ''
    if (option === '--') {
      i++
      break
    }
    if (/^[-+][oO]$/.test(option)) {
      i++
    } else if (/^-[A-Za-z]*c[A-Za-z]*$/.test(option)) {
      hasC = true
    }
  }
  return hasC ? words[i]?.value : undefined
}

// Joins a relative path onto a directory; absolute and `~` paths stand alone.
export function joinPath(base: string | undefined, path: string): string {
  return base === undefined || path.startsWith('/') || path === '~' || path.startsWith('~/') ? path : `${base}/${path}`
}

// The directory after `cd`: null when the shell decides it at run time.
function changeDirectory(cwd: string | null | undefined, args: string[]): string | null | undefined {
  const target = args.filter(a => !['--', '-P', '-L'].includes(a))[0] ?? '~'
  if (cwd === null || target === '-' || target.includes('$') || target.includes('`')) {
    return null
  }
  return joinPath(cwd, target)
}

// Records one command, reading through wrappers, and returns the directory
// the next command in the line runs in.
function unwrap(
  { words, redirects }: Lexed,
  depth: number,
  out: ShellCommand[],
  isSudo: boolean,
  cwd: string | null | undefined,
): string | null | undefined {
  let rest = words
  const isOption = () => rest[0]?.value.startsWith('-') === true
  // A command read as a string elsewhere keeps its redirections here.
  const nested = (text: string) => {
    if (redirects.length > 0) {
      out.push({ argv: [], raw: [], isSudo, redirects, cwd })
    }
    parseInto(text, depth + 1, out, isSudo, cwd)
    return cwd
  }
  for (let head = rest[0]; head !== undefined; head = rest[0]) {
    const name = basename(head.value)
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(head.value)) {
      rest = rest.slice(1)
    } else if (WRAPPERS.has(name)) {
      rest = rest.slice(1)
      while (isOption()) {
        rest = rest.slice(WRAPPER_VALUED[name]?.has(rest[0]?.value ?? '') === true ? 2 : 1)
      }
      if (name === 'timeout') {
        rest = rest.slice(1)
      }
    } else if (name === 'sudo') {
      isSudo = true
      rest = rest.slice(1)
      while (isOption()) {
        rest = rest.slice(/^-[ugpCDhrt]$/.test(rest[0]?.value ?? '') ? 2 : 1)
      }
    } else if (name === 'rtk' || name === 'rtk-run') {
      rest = rest.slice(1)
      if (rest[0]?.value === 'proxy') {
        rest = rest.slice(1)
      }
      if (rest.length === 1 && rest[0] !== undefined) {
        return nested(rest[0].value)
      }
    } else if (name === 'eval') {
      return nested(rest.slice(1).map(w => w.value).join(' '))
    } else if (SHELLS.has(name)) {
      const script = shellScript(rest)
      if (script === undefined) {
        break
      }
      return nested(script)
    } else {
      break
    }
  }
  if (rest.length > 0 || isSudo || redirects.length > 0) {
    out.push({ argv: rest.map(w => w.value), raw: rest.map(w => w.raw), isSudo, redirects, cwd })
  }
  return basename(rest[0]?.value ?? '') === 'cd' ? changeDirectory(cwd, rest.slice(1).map(w => w.value)) : cwd
}

function parseInto(text: string, depth: number, out: ShellCommand[], isSudo = false, cwd?: string | null): void {
  if (depth > MAX_DEPTH) {
    return
  }
  const substitutions: string[] = []
  let dir = cwd
  for (const command of lex(text, substitutions)) {
    dir = unwrap(command, depth, out, isSudo, dir)
  }
  for (const body of substitutions) {
    parseInto(body, depth + 1, out, false, cwd)
  }
}

export function parseCommands(text: string): ShellCommand[] {
  const out: ShellCommand[] = []
  parseInto(text, 0, out)
  return out
}

// The subcommand of a CLI and the arguments after it, skipping global options.
// `valued` lists the global options that take the next word as their value.
export function subcommand(argv: string[], valued: ReadonlySet<string>): { name: string; args: string[] } | null {
  for (let i = 1; i < argv.length; i++) {
    const word = argv[i] ?? ''
    if (!word.startsWith('-')) {
      return { name: word, args: argv.slice(i + 1) }
    }
    if (valued.has(word)) {
      i++
    }
  }
  return null
}

// True when a short-option cluster (`-rf`) or the long option is present.
export function hasFlag(args: string[], short: string, long?: string): boolean {
  return args.some(a => (long !== undefined && a === long) || (/^-[A-Za-z]+$/.test(a) && a.slice(1).includes(short)))
}
