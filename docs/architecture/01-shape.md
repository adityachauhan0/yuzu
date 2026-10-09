# Shape

## Two runtimes, one process

The shipped app is one `Yuzu.app`. Uzu’s xcframework is linked in. MCP servers the user configures are the only child processes.

```text
SwiftUI  ->  Harness  ->  UzuTurn  ->  uzu Engine
                |
                +-> builtin tools (files, shell)
                +-> MCP clients (stdio or HTTP)
```

There is no OpenAI-compatible side server and no second copy of the model. Uzu’s own guidance is one loaded model at a time. Subagents reuse that model serially. They do not load another one.

## What is durable

SQLite under Application Support is the source of truth. A uzu `ChatSession` is a warm cache of the current context epoch, not the record.

Tables, conceptually:

- `sessions` — id, project path, agent id, model identifier, epoch id
- `messages` — ordered session history, including tool calls and tool results
- `inbox` — admitted prompts not yet promoted into history
- `epochs` — baseline system text and the snapshot of context-source values
- `permission_rules` — saved allows for a project
- `permission_requests` — pending asks
- `mcp_servers` — name, transport, enabled
- `agents` — built-in plus user-defined, stored as documents

A crash recovers from these rows. It does not recover from the uzu session. The next drain resets uzu and replays the projected history. See [Uzu boundary](09-uzu-boundary.md).

## OpenCode names we keep

OpenCode’s `CONTEXT.md` is the glossary. Yuzu uses the same words.

| OpenCode | Yuzu meaning |
| --- | --- |
| Admitted prompt | User input on disk, not yet in model history |
| Prompt promotion | Inbox entry becomes a user message |
| Provider turn | One uzu `reply` |
| Session drain | In-process loop that promotes input and runs turns until idle |
| Context source | One keyed fact (instructions, skills, date, MCP instructions) |
| Baseline system context | Text frozen at the start of an epoch |
| Context epoch | Span where that baseline stays valid |
| Mid-conversation system message | Durable note that a source changed |
| Safe provider-turn boundary | The moment just before a uzu call, after promotion and tool settlement |
| Model tool output | The size-capped text actually sent back to the model |

A session drain has no id and is not stored. Recovery looks at the inbox, history, and unfinished tool calls.

## Extension seams

Three ways to add behavior, matching OpenCode’s split:

- **Builtin tools** live in the app. Read, write, edit, glob, grep, bash, skill.
- **MCP** is out of process. A server’s tools are registered beside builtins for the turns where that server is connected.
- **In-process plugins** register tools, skill sources, and context sources. The first plugins are the ones shipped in the app (the skill tool, the customize-yuzu skill). There is no JavaScript plugin host.

Hooks are not a fourth system. A plugin that needs “before bash” wraps the bash tool or adds a permission rule.
