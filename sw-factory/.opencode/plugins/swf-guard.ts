import type { Plugin } from "@opencode-ai/plugin"
import { spawnSync } from "node:child_process"
import { existsSync } from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

// sw-factory guard for OpenCode: the counterpart of the Claude Code PreToolUse hook.
//
// - Ownership and consultation: every write / edit / apply_patch / task call made by a factory
//   agent is translated into the hook input that .opencode/swf-tools/hooks/guard.sh already
//   understands, so both runtimes enforce one policy from one script (tests/guard-test.sh).
//   Exit 2 from the guard blocks the call, and its message reaches the agent as the tool error.
// - Nesting: builders, the planner and the architect consult swf-po / swf-architect themselves
//   (manager → builder → architect → swf-po is three levels). OpenCode allows one level unless
//   `subagent_depth` says otherwise, so this plugin raises it to MIN_DEPTH.
//
// Shell redirection is not covered, in either runtime; swf-qa's drift check is the backstop.

// Only the plugin may be exported: OpenCode calls every export of a plugin file as a plugin.
const MIN_DEPTH = 3

// <root>/.opencode/plugins/swf-guard.ts → <root>
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..")
const GUARD = path.join(ROOT, ".opencode", "swf-tools", "hooks", "guard.sh")

type HookInput = { tool_name: string; agent_type: string; tool_input: Record<string, string> }

// The files an apply_patch call touches: every Add/Update/Delete target and every Move destination.
function patchPaths(patchText: string): string[] {
  const out: string[] = []
  for (const line of String(patchText ?? "").split(/\r?\n/)) {
    const m = /^\*\*\* (?:Add File|Update File|Delete File|Move to):\s*(.+?)\s*$/.exec(line)
    if (m) out.push(m[1])
  }
  return out
}

// The guard inputs one OpenCode tool call stands for; empty when the tool is not governed.
function guardInputs(tool: string, args: any, role: string): HookInput[] {
  const a = args ?? {}
  switch (tool.toLowerCase()) {
    case "write":
      return [{ tool_name: "Write", agent_type: role, tool_input: { file_path: String(a.filePath ?? "") } }]
    case "edit":
      return [{ tool_name: "Edit", agent_type: role, tool_input: { file_path: String(a.filePath ?? "") } }]
    case "apply_patch":
      return patchPaths(a.patchText).map((file_path) => ({ tool_name: "Write", agent_type: role, tool_input: { file_path } }))
    case "task":
      return [{ tool_name: "Task", agent_type: role, tool_input: { subagent_type: String(a.subagent_type ?? "") } }]
    default:
      return []
  }
}

// Runs the guard once; returns its block message, or undefined when the call is allowed.
function runGuard(input: HookInput, cwd: string): string | undefined {
  if (!existsSync(GUARD)) return undefined // preflight reports a missing guard
  const r = spawnSync("bash", [GUARD], {
    input: JSON.stringify(input),
    cwd,
    env: { ...process.env, SWF_PROJECT_DIR: ROOT },
    encoding: "utf8",
  })
  if (r.status === 2) return (r.stderr || "sw-factory guard: blocked").trim()
  return undefined
}

export const SwfGuard: Plugin = async ({ client, directory }) => {
  const agents = new Map<string, string>()

  async function agentOf(sessionID: string): Promise<string> {
    const known = agents.get(sessionID)
    if (known) return known
    try {
      const res: any = await (client as any).session.get({ path: { id: sessionID } })
      const agent = res?.data?.agent ?? res?.agent
      if (typeof agent === "string" && agent) {
        agents.set(sessionID, agent)
        return agent
      }
    } catch {
      // unknown session: treated as the plain main session, which is not governed
    }
    return ""
  }

  return {
    config: async (cfg: any) => {
      if ((cfg.subagent_depth ?? 1) < MIN_DEPTH) cfg.subagent_depth = MIN_DEPTH
    },
    "chat.message": async (input) => {
      if (input.agent) agents.set(input.sessionID, input.agent)
    },
    "tool.execute.before": async (input, output) => {
      const role = await agentOf(input.sessionID)
      if (!role.startsWith("swf-") && !role.startsWith("opsx-")) return
      for (const call of guardInputs(input.tool, output?.args, role)) {
        const blocked = runGuard(call, directory || ROOT)
        if (blocked) throw new Error(blocked)
      }
    },
  }
}
