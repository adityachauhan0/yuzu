# Client

SwiftUI subscribes to harness events and sends commands. It does not import `Uzu`, evaluate permission rules, or read skill files for the model. It can read them to render a preview.

## Commands

- `prompt(session, text, delivery: steer | queue)`
- `cancel(session)`
- `replyPermission(id, once | always | reject)`
- `setAgent(session, id)`
- `compact(session)`
- `mcpConnect(name)` / `mcpDisconnect(name)`
- `loadModel(identifier)` / `ejectModel()`

## Events

The transcript is a projection of stored messages plus live deltas:

- `message.updated` — a row inserted or replaced (streaming assistant text replaces the same id)
- `permission.asked` / `permission.replied`
- `session.status` — `idle` | `draining` | `compacting` | `waiting_permission`
- `mcp.status` — per server
- `model.status` — `empty` | `downloading` | `loaded` | `failed`, plus identifier

Streaming does not create a message per token. The client patches the assistant row’s text and reasoning.

## Screens

The window is specified in [UI](12-ui.md). It is the design handoff in `design/product-handoff/`: one sidebar, a Code mode and a Cowork mode, and the settings modal. Do not replace that shell with a three-column harness debugger.

Permission asks use the existing popover, anchored to the tool row: **Allow once**, **Always**, **Deny**. They do not introduce a new window. One drain at a time. The task list is the set of sessions. Reference names in the handoff (Claude, sample models, the owner’s paths) are resolved in [UI](12-ui.md). The painted layout is not.

## What stays out of the client

System baseline text, context snapshots, and tool-schema messages are not rendered as chat bubbles. A debug disclosure can show the baseline. The default transcript hides them.
