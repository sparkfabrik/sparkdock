import { describe, expect, test } from 'claude-code/testing'
import { commitMessage, detectFormat, findCommits, hasIssueReference, subjectProblem } from './commit-rules'
import { destructiveReason, hasCredentialUrl, isSecretPath, pushesCurrentBranch, secretCandidates } from './guard-rules'
import { parseCommands } from './shell'

const argvs = (command: string) => parseCommands(command).map(c => c.argv)
const reason = (command: string, branch?: string) => parseCommands(command).map(c => destructiveReason(c, branch)).find(r => r !== undefined)

describe('shell', () => {
  test('splits separators, quotes and wrappers', () => {
    expect(argvs(`cd /tmp && FOO=1 rtk-run "git status" ; echo 'a b' | grep -v "x"`)).toEqual([
      ['cd', '/tmp'],
      ['git', 'status'],
      ['echo', 'a b'],
      ['grep', '-v', 'x'],
    ])
  })

  test('reads into bash -c, sudo and command substitutions', () => {
    expect(argvs(`bash -c "rm -rf build"`)).toEqual([['rm', '-rf', 'build']])
    expect(parseCommands('sudo -u root rm x')[0]?.isSudo).toBe(true)
    expect(argvs('echo $(git rev-parse HEAD)')).toEqual([['echo', '$(git rev-parse HEAD)'], ['git', 'rev-parse', 'HEAD']])
  })

  test('skips heredoc bodies and redirect targets', () => {
    expect(argvs("cat > out.txt <<'EOF'\nrm -rf /\nEOF\necho done")).toEqual([['cat'], ['echo', 'done']])
  })

  test('keeps a heredoc inside a substitution whole, apostrophes included', () => {
    const command = `git commit -m "$(cat <<'EOF'\nfix(x): don't break\n\nRefs: a/b#1\nEOF\n)"`
    expect(argvs(command)[0]).toEqual(['git', 'commit', '-m', "$(cat <<'EOF'\nfix(x): don't break\n\nRefs: a/b#1\nEOF\n)"])
  })
})

describe('command guard rules', () => {
  test('credentials in URLs', () => {
    expect(hasCredentialUrl('git clone https://oauth2:glpat-abc@gitlab.sparkfabrik.com/g/p.git')).toBe(true)
    expect(hasCredentialUrl('git clone https://${GITLAB_TOKEN}@gitlab.sparkfabrik.com/g/p.git')).toBe(true)
    expect(hasCredentialUrl('git remote set-url origin https://ghp_x@github.com/o/r')).toBe(true)
    expect(hasCredentialUrl('git clone https://gitlab.sparkfabrik.com/g/p.git')).toBe(false)
    expect(hasCredentialUrl('git clone git@gitlab.sparkfabrik.com:g/p.git')).toBe(false)
    expect(hasCredentialUrl('psql postgres://user:pass@localhost/db')).toBe(false)
  })

  test('secret paths follow the org policy', () => {
    for (const path of ['.env', 'app/.env.local', '.env.prod.local', '.env.staging', 'secrets/db.txt', 'client_secret.json', 'aws-credentials', 'tls.pem', 'id.key']) {
      expect(isSecretPath(path)).toBe(true)
    }
    for (const path of ['.env.example', '.env.dist', 'README.md', 'src/env.ts', 'keys.json']) {
      expect(isSecretPath(path)).toBe(false)
    }
    expect(parseCommands('ls -la .env').flatMap(secretCandidates)).toEqual([])
    expect(parseCommands('cat .env | head').flatMap(secretCandidates)).toEqual(['.env'])
    expect(parseCommands('gcloud secrets versions access latest').flatMap(secretCandidates)).toEqual(['secrets'])
  })

  test('destructive commands', () => {
    expect(reason('rm -rf build')).toBe('deletes recursively')
    expect(reason('rm -r -f build')).toBe('deletes recursively')
    expect(reason('rm -f a.tmp')).toBeUndefined()
    expect(reason('git push --force origin feat/x')).toBe('force-pushes')
    expect(reason('git push origin +feat/x')).toBe('force-pushes')
    expect(reason('git push --force-with-lease')).toBe('force-pushes')
    expect(reason('git push origin HEAD:master')).toBe('pushes to master')
    expect(reason('git push origin main')).toBe('pushes to main')
    expect(reason('git push -u origin feat/x')).toBeUndefined()
    expect(reason('git push', 'master')).toBe('pushes to master')
    expect(reason('git push -u origin HEAD', 'feat/x')).toBeUndefined()
    expect(reason('git -C repo reset --hard HEAD~1')).toBe('discards local changes (git reset --hard)')
    expect(reason('git clean -fd')).toBe('deletes untracked files (git clean -f)')
    expect(reason('git branch -D old')).toBe('force-deletes a branch (git branch -D)')
    expect(reason('git branch -d old')).toBeUndefined()
    expect(reason('terraform -chdir=infra apply')).toBe('changes infrastructure (terraform apply)')
    expect(reason('terraform plan')).toBeUndefined()
    expect(reason('kubectl -n prod delete pod x')).toBe('changes the cluster (kubectl delete)')
    expect(reason('kubectl get pods')).toBeUndefined()
    expect(reason('docker system prune -af')).toBe('prunes Docker data (docker system prune)')
    expect(reason('docker volume rm data')).toBe('removes Docker volumes (docker volume rm)')
    expect(reason('docker rm -f web')).toBe('force-removes containers (docker rm -f)')
    expect(reason('sudo ls')).toBe('runs as root with sudo')
    expect(reason('echo rm -rf')).toBeUndefined()
  })

  test('only branchless pushes need the current branch', () => {
    expect(parseCommands('git push').some(pushesCurrentBranch)).toBe(true)
    expect(parseCommands('git push origin HEAD').some(pushesCurrentBranch)).toBe(true)
    expect(parseCommands('git push origin feat/x').some(pushesCurrentBranch)).toBe(false)
  })
})

describe('commit gate rules', () => {
  test('reads -m, clusters, heredocs and trailers', () => {
    expect(commitMessage(['-m', 'feat: a', '-m', 'body'])).toEqual({ parts: ['feat: a', 'body'], file: undefined })
    expect(commitMessage(['-am', 'fix: b'])).toEqual({ parts: ['fix: b'], file: undefined })
    expect(commitMessage(['--message=docs: c', '--trailer', 'Refs=o/r#1'])).toEqual({ parts: ['docs: c', 'Refs: o/r#1'], file: undefined })
    expect(commitMessage(['-m', "$(cat <<'EOF'\nfeat: d\n\nRefs: o/r#2\nEOF\n)"])).toEqual({ parts: ['feat: d\n\nRefs: o/r#2'], file: undefined })
    expect(commitMessage(['-F', 'msg.txt'])).toEqual({ parts: [], file: 'msg.txt' })
    expect(commitMessage(['-m', '$MSG'])).toEqual({ skip: 'dynamic' })
    expect(commitMessage(['--amend', '--no-edit'])).toEqual({ skip: 'editor' })
    expect(commitMessage(['--fixup', 'abc'])).toEqual({ skip: 'reuse' })
  })

  test('finds commits behind git global options', () => {
    expect(findCommits('git add . && git -C repo commit -m "fix: x"').map(c => c.message)).toEqual([{ parts: ['fix: x'], file: undefined }])
    expect(findCommits('git log --grep commit')).toEqual([])
  })

  test('detects the repository format', () => {
    expect(detectFormat(['feat: a', 'fix(x): b', 'Merge branch y', 'refs #1: c'])).toBe('conventional')
    expect(detectFormat(['refs #1: a', 'refs #2: b'])).toBe('legacy')
    expect(detectFormat(['ACME-1: a'])).toBe('jira')
    expect(detectFormat(['initial', 'wip'])).toBeUndefined()
    expect(detectFormat(['refs #1: a', 'feat: b'])).toBe('legacy')
  })

  test('subject and footer checks', () => {
    expect(subjectProblem('feat(mods): add guard', 'conventional')).toBeUndefined()
    expect(subjectProblem('Add guard', 'conventional')).toMatch(/conventional commit subjects/)
    expect(subjectProblem(`feat: ${'x'.repeat(80)}`, 'conventional')).toMatch(/characters/)
    expect(subjectProblem('Add guard', undefined)).toBeUndefined()
    expect(subjectProblem('Merge branch main', 'conventional')).toBeUndefined()
    expect(hasIssueReference('feat: a\n\nRefs: o/r#1', 'conventional')).toBe(true)
    expect(hasIssueReference('feat: a\n\nCloses: o/r#1', 'conventional')).toBe(true)
    expect(hasIssueReference('feat: a', 'conventional')).toBe(false)
    expect(hasIssueReference('refs #3: a', 'legacy')).toBe(true)
  })
})
