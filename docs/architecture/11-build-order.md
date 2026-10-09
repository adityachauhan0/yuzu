# Build order

Each slice is a running app. Later slices add services behind the same session drain. They do not replace it.

## 1. Model-turn spike

Load one small tool-capable model. Send one `withToolNamespaces` schema. Register no foreign tool. Set `toolTurnLimit` to 0. Confirm `toolCalls()` is populated and a hand-built `toolCallResult` on the next `reply` produces a final answer.

If tool calls only appear when the tool is registered, stop and record that. The fallback is `ForeignTool.invokeJson` blocking on the harness. Do not build the rest of the loop on a guess.

## 2. Drain and read-only tools

SQLite history and inbox. Drain promotes a prompt, calls `UzuTurn`, settles `read`, `glob`, and `grep` with no permission UI (agent rules allow them). SwiftUI shows the stream and the tool cards. Reset-and-replay works, verified by killing the process mid-turn and continuing.

## 3. Permissions

`edit` and `bash` exist and always ask. The sheet replies once, always, or reject. Saved allows persist per project. The plan agent is a second ruleset that denies both, switched from the picker.

## 4. Context sources

Instructions (`YUZU.md` / `AGENTS.md`) and the workspace source form a real baseline stored on the epoch. A change to `YUZU.md` during a session shows up as one mid-conversation system message on the next turn, not as a silent prompt edit.

## 5. Skills

Directory plus embedded sources. Guidance source lists names. The `skill` tool returns the body. `customize-yuzu` is the embedded skill.

## 6. MCP tools

Stdio connect, tool registration under `mcp_<server>_<tool>`, permission ask, disconnect unregisters. HTTP with a static header is in this slice. OAuth is the slice after the loop is bored of stdio.

## 7. Compaction

Overflow at the boundary summarizes and starts a new epoch. Replay after compaction is the test: the model can still name a fact that lived only in the dropped head, because it is in the summary.

## 8. The rest of MCP, then subagents

Prompts as slash commands, `read_resource`, OAuth. Then the `task` tool and a child drain on the same `UzuTurn` lock.

Plugins beyond the shipped skill and MCP bridges wait until a builtin cannot be expressed as a tool, a skill, or an MCP server.
