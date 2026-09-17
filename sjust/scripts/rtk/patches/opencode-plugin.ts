// RTK OpenCode plugin (OpenCode 2.x plugin API).
//
// Sparkdock installs this file over the `rtk.ts` that `rtk init --opencode`
// generates. rtk still emits the OpenCode 1.x shape (a named export returning
// a hooks object), which OpenCode 2.x refuses to load:
//   "Plugin must export a default definition with an id and an effect or
//    setup function."
// Tracked upstream: https://github.com/rtk-ai/rtk/issues/3898
// Remove this patch once `rtk init --opencode` ships an OpenCode 2.x plugin.
//
// Behaviour is the same as the upstream plugin: every bash/shell tool command
// is passed through `rtk rewrite`, which is the single source of truth for the
// rewrite rules. On any error the command runs unchanged.
// Requires: rtk >= 0.23.0 in PATH.

import { execFile } from "node:child_process"

// Resolves with stdout whenever the process ran, whatever its exit code
// (`rtk rewrite` exits 3 on a successful rewrite and 1 when the command is
// excluded). Rejects only when the process could not be spawned at all.
function run(cmd: string, args: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile(cmd, args, { encoding: "utf8" }, (error, stdout) => {
      if (error && typeof (error as NodeJS.ErrnoException).code === "string") {
        reject(error)
        return
      }
      resolve(String(stdout ?? ""))
    })
  })
}

export default {
  id: "rtk",
  async setup(ctx: any) {
    try {
      await run("rtk", ["--version"])
    } catch {
      console.warn("[rtk] rtk binary not found in PATH — plugin disabled")
      return
    }

    await ctx.tool.hook("execute.before", async (input: any) => {
      const tool = String(input?.tool ?? "").toLowerCase()
      if (tool !== "bash" && tool !== "shell") {
        return
      }
      const args = input?.input
      if (!args || typeof args !== "object") {
        return
      }

      const command = (args as Record<string, unknown>).command
      if (typeof command !== "string" || !command) {
        return
      }

      try {
        const rewritten = (await run("rtk", ["rewrite", command])).trim()
        if (rewritten && rewritten !== command) {
          ;(args as Record<string, unknown>).command = rewritten
        }
      } catch {
        // rtk rewrite failed — pass through unchanged
      }
    })
  },
}
