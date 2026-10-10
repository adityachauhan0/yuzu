# V1 implementation plan

Everything in [15-opencode-v1-map.md](15-opencode-v1-map.md) is in V1. OAuth and non-uzu models stay out. Do not add a plugin runtime. Remove the Plugins tab so the window does not ship a dead page.

The engine already runs the session, the builtins, permissions, skills, MCP, compaction, and subagents. This plan makes the window show that, and adds the missing harness pieces.

Theme rule for every new control: colors come from `ThemeColors` / `Tokens`. No new `Color(red:)` literals. No SwiftUI `Menu` for the account row. No `Toggle` with `.switch`. Model and effort are two controls. The decorative cat under a reply goes away.

## 1. Thread

While `turnRunning` is true and no reply text has arrived, the thread shows **Thinking**. It stays until assistant text arrives.

Each settled tool is its own row, collapsed by default, expandable:

| Tool | Title | Detail |
| --- | --- | --- |
| `read` | Read | file name |
| `write` | Write | file name |
| `edit` | Edit | file name |
| `bash` | Shell | the command |
| `grep` | Grep | the pattern |
| `glob` | Glob | the pattern |
| `skill` | Skill | Loaded {name} |
| `task` | Task | the child prompt's first line |
| `todowrite` | Todos | the summary already returned |

A row opens to the result text. Several calls in one turn group as "Used N tools" and expand to those rows. Reasoning, when present, is a collapsed **Thought** row. Verbose mode is gone as a substitute for this.

The thread footer shows context used and percent of `contextLength`, and tok/s for the turn that just finished. Unknown values render "—".

Model and effort are separate buttons on the thread and on Code. Copy stays, without the cat mark under the reply.

## 2. Sidebar pages

**Projects.** Lists known project folders. Choosing one sets the next task's folder. A row opens a new task in that folder. Empty state can still say there is no project, and its button chooses a folder.

**Artifacts.** Lists files the current and past tasks wrote. A row opens the file. The turn's writes and edits are also a review list on the task, with path and whether it was a write or an edit. A full diff view is the review body when the file is text.

**Scheduled.** The page lists real scheduled tasks and creates them. Sample cards may fill the create dialog. The empty illustration is not the product. Keep awake still holds the app awake while a schedule is armed.

**Customize.** Skills stay a real list. Connectors becomes the MCP server list: name, status, add, remove, edit the saved `mcp.json`, connect. Plugins tab is removed.

## 3. Harness pieces that are not in the window yet

**Plan / build.** The composer can switch the session's agent between build and plan. Plan still cannot edit.

**Compaction.** When a turn compacts, the thread shows one line that the earlier context was summarized.

**Subagent.** A `task` call shows the child as a Task row. Opening it shows the child transcript.

**Question.** A `question` builtin. The model asks, the window shows the question, the answer goes back as the tool result.

**Web fetch.** A `webfetch` builtin. One URL, the text of the page, truncated like other tool output. No web search provider.

**Live shell.** `bash` streams output into the Shell row while the command runs, then settles.

**Revert.** Revert drops the last user turn and everything after it in that session, and rewinds the model cursor. The thread offers it on the latest turn.

**Transcript search.** The workspace search already finds task titles. Inside an open thread, a find field filters that transcript.

**Queue.** A prompt sent while a turn is running waits, and starts when the drain is idle.

## 4. Chrome

The account row is a custom popover, not a SwiftUI `Menu`, with the same items: version, Settings, Language (one checked row, English), Inference configuration, changelog, Learn more, Sign out. It is inset from the bottom and the sidebar edges.

Keep awake, Memory, and Response completions use the same custom switch, built from `toggleOn` / `toggleOnText`.

## Evals

Existing suites stay green: `swift test`, `YUZU_EVAL_MODEL=1 swift test --filter LiveUzuTests`, and `YuzuTests` including R1 and R2. R1 and R2 are not weakened.

New harness tests:

- A tool-row formatter maps `read` of `secret.txt` to title Read and detail `secret.txt`, and the same for write, edit, bash, grep, glob, skill, task.
- A question call stores the question and completes when the answer is supplied.
- Web fetch of a local fixture URL returns the fixture text, truncated when it is long.
- Revert removes the last user message and every message after it, and sets `modelMessageCursor` back.
- A prompt admitted while a drain is running is still in the inbox until that drain finishes, then it runs.
- Compaction still passes K1–K4, and the session records that a summary replaced the head.

New window tests, no live model:

- While a turn is marked running and the transcript has no assistant text yet, the thread exposes the label Thinking.
- The secret.txt settlement renders a row labeled Read, detail `secret.txt`, collapsed. Expanding reveals the result.
- The thread footer exposes context percent and tok/s identifiers.
- Model and effort are two controls.
- Projects lists a known folder and choosing it sets the next project path.
- Artifacts lists a written file. The review row says write or edit.
- Connectors lists a server from `mcp.json`. There is no Plugins tab.
- The account control is not a native menu. The keep-awake control is not a system switch.
- Revert on the latest turn removes it from the transcript.
- Find inside the thread filters to the matching line.

Theme check, read only: new and touched views use `ThemeColors` or `Tokens`. Flag any new `Color(red:)`, `Color(white:)`, `.switch`, or SwiftUI `Menu` used for the account row, model, or effort.

## Order

1. Thread rows, Thinking, footer, model/effort split, copy without the cat.
2. Account popover, custom switches, Projects, Artifacts review, MCP list, drop Plugins.
3. Plan/build, compaction line, Task row, question, webfetch, live shell, revert, transcript find, queue.
4. Run the suites above. Do not commit unless asked.
