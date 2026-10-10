# Tools

A tool is a name, a description, a JSON schema for the input, and an execute function. OpenCode’s `Tool.make` is the pattern: decode input, run, encode output, then optionally rewrite what the model sees (`toModelOutput`). The registry enforces the size cap after that.

Names match `^[A-Za-z][A-Za-z0-9_-]{0,63}$`.

## Registry

`ToolRegistry.materialize(rules)` returns:

- the definitions to send on the next uzu turn
- a `settle` function closed over that exact set

Settle checks the call’s name against the set from that turn. A call the model invented for a tool that was not advertised, or a tool removed since the turn started, is a tool error: `Unknown tool` or `Stale tool call`. It is not an exception that kills the drain.

A tool whose permission action is denied for resource `*` is left out of materialize entirely. The model is not told it exists.

Registration is scoped. Builtins register for the life of the process. An MCP server’s tools register when it connects and unregister when it disconnects. Plugins register in the same map. Later registration of the same name shadows the earlier one until that scope ends.

## Builtins

| Name | Permission action | Does |
| --- | --- | --- |
| `read` | `read` | File text, size-capped, path inside the project unless approved |
| `glob` | `glob` | Names by pattern |
| `grep` | `grep` | Content search |
| `write` | `edit` | Create or replace a file |
| `edit` | `edit` | One exact string replace. Fail if the match is missing or ambiguous |
| `bash` | `bash` | One command, timeout, truncated output. Working directory is the project. No persistent shell |
| `skill` | `skill` | Load one skill body. See [Skills](06-skills.md) |
| `todowrite` | none | Replace the session's step list (`content`, `status`). The inspector's Progress draws it |

`write` and `edit` share the `edit` action so one allow rule covers both. Paths are the permission resource (`edit` on `src/main.swift`). Bash’s resource is the command string. The gate can also match a prefix later; v1 of the rule language is wildcard on the whole string, same as OpenCode’s `Wildcard.match`.

## Output

The model sees a bounded projection. Default cap is the same idea as OpenCode’s tool-output store: if the raw output exceeds the cap, write the full output under Application Support `tool-output/<session>/<call-id>` and put a short text plus that path in the tool result. The model can `read` the file if it needs the rest. The UI can open the full output from the path.

Tool results are plain text in the uzu message (`toolCallResult`). File parts (images) wait until a model in the catalog actually accepts them. The tool interface still has a content array so we do not repaint it later: `text` or `file`.

## Multiple calls

If `ChatModelCapabilities.supports_multiple_tool_calls` is false, keep only the first call, drop the rest from the stored assistant message, and continue. If it is true, run calls one after another in listed order, then send every result on the next turn. Parallel execution is not worth the permission-prompt interleaving.

## Where this hits uzu

Materialized definitions become one `ToolNamespace` named `yuzu`. Each definition is a `ToolFunction` (`name`, `description`, `parameters`). Nothing is passed to `addTool` or `addForeignTool`. The engine must not execute tools. [Uzu boundary](09-uzu-boundary.md) says how that namespace is attached to a turn.
