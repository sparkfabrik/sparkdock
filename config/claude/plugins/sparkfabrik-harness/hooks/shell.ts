// Best-effort reading of a Bash command into argv lists, without running it.
// Quotes, escapes, separators, command substitutions, heredocs and the
// wrappers Claude commonly adds are understood; anything else stays literal.

const WRAPPERS = new Set(['command', 'builtin', 'exec', 'nohup', 'time', 'nice'])
const SHELLS = new Set(['bash', 'sh', 'zsh', 'dash'])
const MAX_DEPTH = 4

export type ShellCommand = {
  argv: string[]
  // Raw text of each word, quotes and substitutions kept.
  raw: string[]
  // True when `sudo` wrapped the command.
  isSudo: boolean
}

type Word = { value: string; raw: string }

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

// Splits `text` into commands of words. Substitution bodies are collected so
// the caller can read the commands inside them too.
function lex(text: string, substitutions: string[]): Word[][] {
  const commands: Word[][] = []
  let words: Word[] = []
  let value = ''
  let raw = ''
  let inWord = false
  let skipNext = false
  const heredocs: string[] = []

  const endWord = () => {
    if (inWord) {
      if (skipNext) {
        skipNext = false
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
    if (words.length > 0) {
      commands.push(words)
    }
    words = []
  }

  for (let i = 0; i < text.length; i++) {
    const c = text[i]
    if (c === '\n' && heredocs.length > 0) {
      endCommand()
      // Heredoc bodies are data: skip each one up to its delimiter line.
      for (const delimiter of heredocs.splice(0)) {
        i = heredocEnd(text, i + 1, delimiter)
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
          heredocs.push(match[2] ?? '')
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

function unwrap(words: Word[], depth: number, out: ShellCommand[], isSudo = false): void {
  let rest = words
  const isOption = () => rest[0]?.value.startsWith('-') === true
  for (let head = rest[0]; head !== undefined; head = rest[0]) {
    const name = basename(head.value)
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(head.value)) {
      rest = rest.slice(1)
    } else if (WRAPPERS.has(name) || name === 'env') {
      rest = rest.slice(1)
      while (isOption()) {
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
        parseInto(rest[0].value, depth + 1, out, isSudo)
        return
      }
    } else if (SHELLS.has(name) && rest[1]?.value === '-c' && rest[2] !== undefined) {
      parseInto(rest[2].value, depth + 1, out, isSudo)
      return
    } else {
      break
    }
  }
  if (rest.length > 0 || isSudo) {
    out.push({ argv: rest.map(w => w.value), raw: rest.map(w => w.raw), isSudo })
  }
}

function parseInto(text: string, depth: number, out: ShellCommand[], isSudo = false): void {
  if (depth > MAX_DEPTH) {
    return
  }
  const substitutions: string[] = []
  for (const words of lex(text, substitutions)) {
    unwrap(words, depth, out, isSudo)
  }
  for (const body of substitutions) {
    parseInto(body, depth + 1, out)
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
