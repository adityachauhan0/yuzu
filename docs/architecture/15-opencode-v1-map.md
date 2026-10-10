# OpenCode to Yuzu, for a V1 line

Read of `anomalyco/opencode` (shallow checkout, 2026-10-10) against the Yuzu window on `cursor/harness-architecture` at `c59ce45`.

Yuzu's engine is a reimplementation of OpenCode's harness boundaries. The window is still mostly the Cowork handoff. This note separates those two, so a V1 line can be drawn without treating prototype pages as harness features.

Out of scope, by decision: OAuth, and any model that is not the local uzu model.

## What is already real

A normal launch loads the model uzu advises for this Mac (Qwen3.5 9B on the machine this was checked on). Weights stay in uzu's cache. The app bundle does not contain them.

The harness, not the window, already has:

- Session admit, drain, stop, and SQLite history
- Builtins `read`, `glob`, `grep`, `write`, `edit`, `bash`, `skill`, `task`, `read_resource`, `todowrite`
- Permissions: ask, once, always, reject. The plan agent denies edits
- Skill discovery, including the embedded `customize-yuzu` skill, and the `skill` tool
- MCP: stdio connect, a static HTTP header, prompts as messages, resource read. The config is `mcp.json`
- Compaction when the context boundary is crossed
- Subagent `task` on the same model lock
- Instructions from `YUZU.md` / `AGENTS.md` and the settings instruction files, loaded into the turn

R1, R2, the harness suite, live U1–U3, and the window checks V1–V9 passed on that build. A live thread showed `read` of `secret.txt` returning a nonce that was not in the prompt.

## What the window actually does

These are the complaints, checked against the code and a live window.

**Projects.** An empty panel. The only button is "New task", which leaves the page. It does not list projects and it does not open a folder. Choosing a folder exists on the composer, not here.

**Artifacts.** An empty sentence until a task has written a file, then a flat path list. Not a diff, and not a review of the turn.

**Scheduled.** A real local scheduler: create, keep-awake, fire while the app is running. The page you land on is the prototype empty state, the stopwatch illustration, and six sample cards. This feature is not in OpenCode.

**Customize.** Skills lists real skills from disk. Connectors echoes MCP server lines from the JSON config and does not manage a server. Plugins is the sentence "No plugins yet".

**Thinking and tool calls.** Nothing says "Thinking" while a turn runs. After a tool settles, the thread draws one dim line such as "Used read". Verbose mode appends the raw JSON arguments. OpenCode's session UI (`packages/session-ui`) shows a live status, then one expandable row per call.

**tok/s and context.** OpenCode's TUI footer (`packages/tui/src/util/session.ts`, `formatContextUsage`) shows tokens used and the percent of the model window: `12,400 (18%)`, or `18% ctx` when compact. Yuzu stores a context length on the session and can compute a speed after a Code-home turn that lasted at least half a second. The thread composer shows neither. The Code-home speed stays "—" otherwise.

**Copy.** The button under a reply copies the text and toasts "Copied response." The last reply also draws a decorative cat (`thread-brand`). That cat is not a control. OpenCode puts copy on the message actions and does not draw a mascot there.

**Model and effort.** Code combines them in one popover. On the thread the model is a button and the effort is plain text beside it. They should be two controls. The handoff's single popover is not the target.

**Bottom-left account row.** "Yuzu Beta" is a SwiftUI `Menu`, so the menu is the native macOS menu. The row sits on the bottom of the sidebar with `padding(.vertical, 10)` and no designed inset. Keep awake, Memory, and Response completions use `Toggle` with `.switch`, which is the system switch, not the switch drawn for the handoff.

## One-to-one map

| OpenCode | Where it lives there | Yuzu engine | Yuzu window | V1 suggestion |
| --- | --- | --- | --- | --- |
| Session: send, stream, stop, history | `packages/core/src/session`, app session screen | Done | Send and stop work. No live "Thinking" | Keep |
| Live status while the model works | `ui.sessionTurn.status.thinking` ("Thinking"), plus Planning, Exploring, Making edits, Running commands | The drain runs | The thread is quiet until text or a settled tool appears | Keep. Show "Thinking" for the whole turn until text arrives |
| Tool row: Read + filename | `getToolInfo` in `packages/session-ui/src/tools/tool-renderer.tsx`, title `ui.tool.read` | `read` runs | "Used read" | Keep. One row, expandable |
| Tool row: Write + filename | title `ui.messagePart.title.write` | `write` runs | Folded into the same summary | Keep |
| Tool row: Edit + filename | title `ui.messagePart.title.edit` | `edit` runs | Same | Keep |
| Tool row: Shell + command | title `ui.tool.shell`, subtitle is the command | `bash` runs | "ran N commands", verbose JSON | Keep |
| Tool row: Grep / Glob / List | titles `ui.tool.grep`, `glob`, `list` | `grep` and `glob` run. No `list` | Same summary | Keep Grep and Glob. List can wait |
| Grouped tool summary | "Used N tools", expands to the rows | Settlement is stored | One ungrouped line | Keep the expand |
| Reasoning, collapsed after the turn | "Thought" / "Thoughts" | Reasoning text is stored | Shown only in Thinking or Verbose mode, not as a collapsed row | Keep a collapsed row |
| Context used and % of the window | TUI footer: `formatContextUsage` → `tokens (percent%)` | Context length is on the session. Usage tokens are in the store | Not on the thread footer | Keep |
| tok/s | Not the TUI footer's main figure. Yuzu already invented a post-hoc Code-home speed | Computed after a finished Code turn when it lasted ≥ 0.5s | Thread footer has none. Code home shows "—" most of the time | Decide. Context % is the OpenCode footer. tok/s is extra |
| Permissions: ask, once, always, reject | `packages/core/src/permission`, session permission dock | Done | A permission sheet exists | Keep |
| Plan vs build agent | `packages/core` agents | Done. Plan denies edit | No picker | Decide |
| Skills: discover, load the body into the turn | `packages/core/src/skill`, row "Loaded {name} skill" | Done | Catalog page only. No "Loaded …" row in the thread | Keep the thread row. The catalog page can wait |
| MCP: add, connect, call, disconnect | `packages/core/src/mcp`, settings `servers.tsx` | Stdio and a static HTTP header work. OAuth is out of scope | Developer settings is a JSON textarea. Connectors lists the lines | Keep a real server list |
| Todos | `todowrite` tool row | Done | Inspector shows them only after the model writes them | Keep |
| Subagent / task | tool row "Task" / "{type} Agent" | Done, child session, same lock | No child in the thread | Later |
| Compaction | core session, summarized epoch | Done. Tests K1–K4 | No sign it happened | Later, once the context % is visible |
| File review / diff of the turn | session review v2 | write and edit produce files | Artifacts is a path list | Decide. This is OpenCode's review, not the Artifacts page |
| Projects / workspaces | settings projects, shell project | Composer can set the next folder | Projects page does not list or choose one | Replace that page, or drop it from the sidebar |
| Scheduled tasks | Not in OpenCode | Local scheduler, keep-awake | Prototype empty state and sample cards | Drop for V1 unless scheduling stays a product goal |
| Plugins | Extensions are a settings tab with a real inventory | None | "No plugins yet" | Drop |
| Instructions file | core instructions | Loaded into the turn | Settings text fields | Keep |
| Question tool (the model asks you) | `ui.tool.questions` | Not built | None | Later |
| Web fetch / web search | `webfetch`, `websearch` | Not built | None | Later |
| Live shell output | shell tool streams, "Writing command…" | One command, then the result | No live output | Later |
| Revert / undo a turn | session revert | Not built | None | Later |
| Message queue, background work | composer queue, session timeline | Not built | None | Later |
| Session search | session search bar | Task titles are searchable in the workspace dialog | No search inside a transcript | Later |

## A V1 line

Keep, and make them visible:

- "Thinking" for the whole turn until text arrives
- One expandable row per tool: Read, Write, Edit, Shell, Grep, Glob, with the file name or the command
- Context used and percent of the window, on the thread footer
- Model and effort as two controls
- The permission sheet
- Skills and MCP as the real lists (a loaded-skill row, a server list), not the prototype pages

Take off the sidebar until they are those things: Projects, Artifacts, Scheduled, Customize, Plugins.

Do not copy the handoff's combined model popover, the decorative cat under a reply, the native account menu, or the system switch, just because they are already on screen.
