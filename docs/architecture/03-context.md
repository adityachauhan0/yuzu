# Context

The system text is not one string we rebuild every turn. It is a set of context sources, snapshotted into an epoch, then patched with durable messages when a source changes.

## Sources

Each source has a stable key, a loader, a baseline renderer, an update renderer, and an optional removal renderer. Loaders run at a safe boundary, not on a timer. A source that fails to load keeps its previous value and emits nothing.

Shipped sources, in contribution order:

| Key | Loads | Baseline |
| --- | --- | --- |
| `core/instructions` | `YUZU.md`, else `AGENTS.md`, from the project root upward, then the user-level file | Concatenated markdown, size-capped |
| `core/skill-guidance` | Names and descriptions of skills this agent may use | The available-skills list. Bodies are not here |
| `core/mcp-instructions` | `instructions` from each connected MCP server | Server name plus those instructions |
| `core/workspace` | Project path, git branch if any | A few lines |
| `core/date` | Host-local calendar date | One line |

The agent’s own system addendum is part of the baseline, not a source. Changing agent re-renders skill guidance and can emit an update message. It does not by itself start a new epoch.

Tool schemas are not a context source. They ride on the uzu request for the epoch. A change to the materialized tool list (MCP connect or disconnect, agent permission change that drops a tool) dirties the epoch: reset uzu and replay. See [Uzu boundary](09-uzu-boundary.md).

## Epoch

An epoch starts when a session starts, when compaction finishes, or when the session changes project. The first provider turn of an epoch renders the full baseline and stores it. Later turns reuse that text. Unavailable sources block that first turn and leave the inbox prompt pending. Later, an unavailable source is stale-while-revalidate.

When a source’s value differs from the snapshot, the boundary appends one mid-conversation system message with the update text, then advances the snapshot in the same write. Several sources that changed at one boundary share one message. The message stays in durable history even if the following uzu call fails.

## Compaction

Taken from OpenCode’s `session/compaction.ts`, with their numbers as the defaults:

- Reserve a 20_000 token buffer under the model’s context length.
- Keep the most recent 8_000 tokens of conversation verbatim.
- Truncate a single tool output to 2_000 characters in the summary input.
- Ask the model for a structured markdown summary, at most 4_096 output tokens, with tools off.
- If a previous summary exists, the prompt carries it and the new summary must stand alone.

Compaction is itself a provider turn on the same loaded model. On success, start a new epoch. The projected history becomes: new baseline, the summary as a user-visible compaction message, then the recent tail. Older mid-conversation system messages stay on disk and leave the projection.

If the model metadata has no context length, the session uses a conservative default of 32_768 tokens until the user sets one. `ContextLength` on the uzu chat config (`default`, `maximal`, `custom`) is set from that same number so the engine’s window and the harness budget match.

Auto compaction runs at the boundary when projected tokens plus the buffer exceed the window. The user can also compact from the UI.

## Instructions file

Project rules live in `YUZU.md`. If that file is absent and `AGENTS.md` is present, load `AGENTS.md`. Walk from the project root to the worktree root and concatenate, nearest last, so the closest file wins on contradiction. Cap the aggregate (OpenCode’s instruction source is one ordered aggregate; we cap at 32 KB of text).
