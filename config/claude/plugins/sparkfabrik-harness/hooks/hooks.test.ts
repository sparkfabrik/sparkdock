import type { On } from 'claude-code'
import { describe, expect, mock, test } from 'claude-code/testing'

type World = {
  env?: Record<string, string>
  surfaces?: string[]
  answer?: string
  files?: string[]
  dirs?: string[]
  contents?: Record<string, string>
  branch?: string | Record<string, string>
  subjects?: string[]
  classify?: object | 'fail'
}

// Stands in for the engine beneath the plugin, and records what reached the tools.
function world(on: On, w: World): { ran: string[]; asked: string[]; processes: string[] } {
  const ran: string[] = []
  const asked: string[] = []
  const processes: string[] = []
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
  // The engine may hand a path over resolved against the session's directory.
  const has = (list: string[] | undefined, path: string) => (list ?? []).some(f => path === f || path.endsWith(`/${f}`))
  on('fs.stat', async ($, e) => {
    const kind = has(w.files, e.path) ? 'file' : has(w.dirs, e.path) ? 'dir' : undefined
    return kind === undefined ? { deny: 'ENOENT' } : { value: { kind, size: 1, mtimeMs: 0, isLink: false } }
  })
  on('fs.read', async ($, e) => {
    const text = Object.entries(w.contents ?? {}).find(([f]) => e.path === f || e.path.endsWith(`/${f}`))?.[1]
    return text === undefined ? { deny: 'ENOENT' } : { value: text }
  })
  on('process.run', async ($, e) => {
    const { argv, init } = e as { argv: string[]; init?: { cwd?: string } }
    processes.push(`${init?.cwd ?? '.'}: ${argv.join(' ')}`)
    const branch = typeof w.branch === 'object' ? (w.branch[init?.cwd ?? '.'] ?? 'feat/x') : (w.branch ?? 'feat/x')
    if (argv[0] === 'python3' && w.classify === 'fail') {
      return { value: { exitCode: 2, stdout: '', stderr: 'boom', isStdoutTruncated: false, isStderrTruncated: false } } as never
    }
    const stdout =
      argv[1] === 'branch' ? `${branch}\n` : argv[1] === 'log' ? (w.subjects ?? ['feat: a', 'fix: b']).join('\n') : JSON.stringify(w.classify ?? { required: [], available: [] })
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } } as never
  })
  on('tool.call', async ($, e) => {
    ran.push(e.tool === 'Bash' ? e.command : e.tool)
    return { result: 'ok' } as never
  })
  return { ran, asked, processes }
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

  test('denies reading or writing a secret file through a redirection', async ($, on) => {
    const { ran } = world(on, { files: ['.env'] })
    expect(refusal(await $.tool.call(bash('cat < .env')))).toMatch(/secret file/)
    expect(refusal(await $.tool.call(bash('printf x > .env')))).toMatch(/secret file/)
    expect(ran).toEqual([])
  })

  test('checks secret files where an earlier cd points', async ($, on) => {
    const { ran } = world(on, { files: ['app/.env'] })
    expect(refusal(await $.tool.call(bash('cd app && cat .env')))).toMatch(/secret file/)
    expect(refusal(await $.tool.call(bash('cd "$DIR" && cat .env')))).toMatch(/secret file/)
    expect(ran).toEqual([])
  })

  test('denies a recursive read of a secret directory, not a listing', async ($, on) => {
    const { ran } = world(on, { dirs: ['secrets'] })
    expect(refusal(await $.tool.call(bash('grep -R . secrets')))).toMatch(/secret file/)
    await $.tool.call(bash('ls secrets'))
    await $.tool.call(bash('gcloud secrets versions list'))
    expect(ran).toEqual(['ls secrets', 'gcloud secrets versions list'])
  })

  test('denies the Grep tool on a secret path or glob', async ($, on) => {
    const { ran } = world(on, {})
    const byPath = await $.tool.call({ tool: 'Grep', tool_use_id: 'toolu_5', pattern: 'x', path: '.env', output_mode: 'content' } as never)
    expect(refusal(byPath)).toMatch(/secret file/)
    const byGlob = await $.tool.call({ tool: 'Grep', tool_use_id: 'toolu_6', pattern: 'x', glob: '**/*.pem' } as never)
    expect(refusal(byGlob)).toMatch(/secret file/)
    await $.tool.call({ tool: 'Grep', tool_use_id: 'toolu_7', pattern: 'x', path: 'src' } as never)
    expect(ran).toEqual(['Grep'])
  })

  test('reads the branch where an earlier cd points', async ($, on) => {
    const { ran, asked } = world(on, { answer: 'Cancel', branch: { '.': 'feat/x', other: 'master' } })
    const out = await $.tool.call(bash('cd other && git push'))
    expect(asked[0]).toMatch(/pushes to master/)
    expect(refusal(out)).toMatch(/declined/)
    expect(ran).toEqual([])
  })

  test('asks before a push whose directory the shell decides', async ($, on) => {
    const { asked } = world(on, { answer: 'Run it' })
    await $.tool.call(bash('cd "$DIR" && git push'))
    expect(asked[0]).toMatch(/pushes the current branch, which could not be determined/)
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

  test('recognizes gh quoted inside rtk-run', async ($, on) => {
    const { ran } = world(on, { classify: publish, surfaces: [] })
    const out = await $.tool.call(bash(`rtk-run "gh pr create --title t --body b"`))
    expect(refusal(out)).toMatch(/Load these skills/)
    expect(ran).toEqual([])
  })

  test('asks the person when the classifier fails', async ($, on) => {
    const { ran, asked } = world(on, { classify: 'fail', answer: 'Cancel' })
    const out = await $.tool.call(bash('gh pr create --title t --body b'))
    expect(asked[0]).toMatch(/Publish this\?/)
    expect(refusal(out)).toMatch(/did not publish/)
    expect(ran).toEqual([])
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

  test('reads a relative message file from the git -C repository', async ($, on) => {
    const { ran } = world(on, { contents: { 'repo/msg.txt': 'Add the file\n' } })
    const out = await $.tool.call(bash('git -C repo commit -F msg.txt'))
    expect(refusal(out)).toMatch(/conventional commit subjects/)
    expect(ran).toEqual([])
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
