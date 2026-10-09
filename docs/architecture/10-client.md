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

One window, three columns once the harness is complete. Earlier slices can ship with fewer.

- **Models.** On-device and downloadable chat models that support tools. Download progress. Load and eject. The loaded model is global.
- **Transcript.** Messages, tool cards, reasoning disclosure, the composer, the agent picker, the permission sheet.
- **Inspector.** Session token estimate against the budget, connected MCP servers, skill list (names only), saved permission rules.

The permission sheet is modal for that session only. A second session is not a v1 feature. One drain, one window.

## What stays out of the client

System baseline text, context snapshots, and tool-schema messages are not rendered as chat bubbles. A debug disclosure can show the baseline. The default transcript hides them.
