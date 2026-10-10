# Yuzu harness

Yuzu is a Mac app. The harness is the coding agent. Uzu is the model runtime inside it. SwiftUI is a client of harness events and never calls uzu itself.

The shape comes from [OpenCode](https://github.com/anomalyco/opencode) (`anomalyco/opencode`, MIT), read from `packages/core`. We reimplement those boundaries in Swift. We do not port the TypeScript. Claude Code’s repository does not contain its CLI, so it is not a source.

## Read this order

1. [Shape](01-shape.md) — processes, modules, what is durable
2. [Session loop](02-session-loop.md) — admit, drain, provider turn, idle
3. [Context](03-context.md) — baseline, sources, epoch, compaction
4. [Tools](04-tools.md) — registry, builtins, output limits
5. [Permissions](05-permissions.md) — rules, ask, once / always / reject
6. [Skills](06-skills.md) — discovery, guidance in context, the skill tool
7. [MCP](07-mcp.md) — servers, tools, prompts, resources, auth
8. [Agents](08-agents.md) — build, plan, subagents
9. [Uzu boundary](09-uzu-boundary.md) — the only file that talks about the engine
10. [Client](10-client.md) — events the UI is allowed to see
11. [UI](12-ui.md) — the Code / Cowork window. Looks match the handoff; reference ids are resolved there
12. [Build order](11-build-order.md) — how the complete harness is sliced into working apps
13. [Implementation](13-implementation.md) — file layout, interfaces, and the evals a slice must pass
14. [Uzu Qwen bottleneck](14-uzu-qwen-bottleneck.md) — why a Mirai Qwen turn hit chat-template line 87, and the fix
15. [OpenCode V1 map](15-opencode-v1-map.md) — what OpenCode has, what the engine already does, and what the window still lacks
16. [V1 implementation](16-v1-implementation.md) — the work to make that map true, and the evals that prove it

## Module map

```text
App
  Shell           Code / Cowork window from design/product-handoff
  Models          catalog, download, one loaded model
Harness
  Session         admission, drain, history
  Context         sources, epoch, compaction
  Tools           registry and builtins
  Permission      rules and pending asks
  Skills          sources plus the skill tool
  MCP             out-of-process servers
  Agents          permission sets and step limits
  Store           SQLite
Model
  UzuTurn         Engine, one ChatInstance, turn cache
```

`Harness` can call `Model`. `App` can call `Harness`. `Model` cannot call `Harness`.
