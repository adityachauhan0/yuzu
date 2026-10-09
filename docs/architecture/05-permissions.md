# Permissions

A rule is `{ action, resource, effect }` with effect `allow`, `deny`, or `ask`. Evaluation walks the ruleset from last to first and takes the last wildcard match. If nothing matches, the effect is `ask`.

That is OpenCode’s `PermissionV2.evaluate`.

## Where rules come from

For one assert, in order:

1. The agent’s ruleset. An unknown agent is deny-all (`*` / `*` / `deny`).
2. Saved allows for this project (`once` is not saved; `always` is).

Deny on the agent ruleset wins before saved allows are considered. A saved allow cannot override an agent deny. That is what makes the plan agent actually read-only.

## Agents’ starting rules

**build** (default primary):

- `read`, `glob`, `grep`, `skill` on `*` → allow
- `edit`, `bash` on `*` → ask
- `mcp:*` on `*` → ask

**plan** (primary):

- `read`, `glob`, `grep` on `*` → allow
- `edit`, `bash` on `*` → deny
- `skill` on `*` → allow
- `mcp:*` on `*` → ask

Users add rules in the app. A rule is not a mode enum. The “accept edits” behavior from the earlier sketch is a saved allow of `edit` on `*`, not a third runtime.

## Ask

`assert(action, resources)`:

- Any resource denied → fail the tool with a denial message. No UI.
- Any resource ask, and none deny → insert a `permission_requests` row and an event `permission.asked`. The drain waits.
- Otherwise run the tool.

The request carries `sessionID`, `action`, `resources`, the tool call id, and optional metadata (the command line, the path). The UI shows the action, the resources, and three replies:

- **once** — allow this call only
- **always** — allow this call and append an allow rule for each resource on this project
- **reject** — tool result is a denial, drain continues so the model can recover

Closing the window or quitting fails pending asks as reject.

The agent id is fixed on the request when the call is issued. Switching agent while a prompt is open does not change that call’s policy.

## Events

`permission.asked` and `permission.replied` are the only permission events the client needs. The client replies by id. It does not evaluate rules itself.
