# Uzu boundary

`UzuTurn` is the only type that imports `Uzu`. The harness speaks `TurnRequest` and `TurnEvent`.

## What uzu is responsible for

One `Engine`, one `ChatInstance` for the loaded model, one warm `ChatSession` used as a KV cache for the current epoch.

A provider turn is `replyWithStream` with:

- the delta messages since the cache was last consistent
- `ChatReplyConfig.toolTurnLimit = 0`
- sampling from the session
- `ContextLength` set from the harness budget

No `addTool`. No `addForeignTool`. If a tool is registered, uzu executes it inside `reply` and the permission gate never sees the call. That path is forbidden.

Tool schemas travel as a developer message built with `withToolNamespaces`: one namespace, `yuzu`, whose tools are the materialized `ToolFunction` list. Uzu returns `toolCalls()` on the assistant message (`id`, `name`, `arguments`) and stops, because those names are not registered functions (`has_registered_tool_functions` is false in `nagare`’s chat session). The harness executes them.

This behavior is the spike in [Build order](11-build-order.md). If a model returns tool-call text that uzu does not parse unless the tool was registered, the fallback is a `ForeignTool` per advertised name whose `invokeJson` blocks on the harness settle function. The engine would then own the turn counter. We only take that fallback if the spike fails, and `toolTurnLimit` would be raised to the agent’s step budget so uzu does not stop after one call.

## Cache versus record

`ChatSession.send_input` appends the input onto an internal message list and then runs the full list. SQLite is the record. The session is a cache.

Rules:

- A normal tool round-trip sends only the new messages (tool results, or a promoted user message, or one mid-conversation system message). The cache stays warm. Prefill is not repeated.
- Anything that changes the projected prefix calls `reset()` and replays the projection once. That set is: compaction, epoch change, tool-list change, agent system-text change, model reload, cancel that deleted a partial assistant message, and any detected divergence (cache message count or epoch id does not match the store).

Replay content, in order: baseline system text as a system message, the tool-namespace developer message, then projected history (summary and recent tail after compaction). Mid-conversation system messages from the current epoch are included. Ones from older epochs are not.

Divergence check before every turn: stored epoch id equals the cache’s epoch id, and the cache’s message count equals the length of the last replay plus deltas applied since. On mismatch, reset and replay. Do not try to patch the cache in place.

## Capabilities

The model picker only offers chat models with `supports_tools == true`. A model without tools cannot run this harness.

`supports_multiple_tool_calls == false` is handled in the harness by keeping a single call, as [Tools](04-tools.md) says. Uzu would also truncate, but only inside its own loop, which we are not using.

`requires_tools == true` means the summary turn at max steps still sends the namespace. Calls on that turn settle as errors.

`supports_reasoning` streams reasoning separately from text. The transcript stores both. They are not tool calls.

## One model

`Engine.chat_instance` owns the weights. A second session uses `chat_with_instance` only for a subagent, and only after the parent turn has finished. Two drains never call `reply` at the same time. A lock on `UzuTurn` enforces that.

Download, eject, and load stay on the engine but are invoked by the Models part of the app through a narrow `ModelCatalog` API: list, download, load, eject, current identifier. Loading a model cancels the drain, resets the cache, and starts a new epoch on the next run.

## Sampling

Temperature, top_p, top_k, max tokens, and greedy are session fields passed through on each turn. They are not agent fields. Changing them does not reset the cache.

## Stats

Each turn’s `tokens_count_output` and any input token count uzu reports are stored on the assistant message. Compaction’s token estimate uses those counts when present and a character estimate (`chars / 4`) when not. The estimate is what decides the boundary. It does not have to match the engine’s tokenizer exactly; the buffer of 20_000 tokens exists so it can be wrong.
