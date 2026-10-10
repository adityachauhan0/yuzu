# Why a Mirai Qwen turn died before the first token, and the fix

R2 loads `alibaba:qwen3.5:9b:mirai:mirai-m:4` and used to abort inside uzu with:

```text
Yuzu model turn failed: session("Backend(message: \"Render failed: invalid operation: System message must be at the beginning. (in chat_template:87)\")")
```

Status: fixed in `Sources/YuzuModel/UzuTurn.swift`. R2 passes: the model calls `read` on `secret.txt` and replies with the nonce. uzu 0.6.2 is unmodified.

## The line that throws

uzu renders this checkpoint with the bundled Qwen 3.5 template (`crates/legacy/hanashi/configs/rendering/qwen3.5.json`, the same text ships in the model's `config.json`). Line 87:

```jinja
{%- for message in messages %}
    {%- set content = render_content(message.content, true)|trim %}
    {%- if message.role == "system" %}
        {%- if not loop.first %}
            {{- raise_exception('System message must be at the beginning.') }}
```

A system message is legal only at index 0 of the array the template walks.

## Which array it walked

`ChatSession` keeps every message it has been sent. `send_input` appends the new input onto that vector and renders the whole thing (`nagare/src/chat/mod.rs`). `reset()` clears it.

Logging the roles per turn on the failing run showed:

```text
turn 1  delta=[system, user]               sent=[system, developer, user]  session before=[]
turn 2  delta=[system, tool, system]       sent=[system, tool]             session before=[system, developer, user, assistant]
```

Turn 1 rendered fine. Turn 2, the continuation after the `read` tool ran, failed. Two system messages entered its delta:

1. `ContextCoordinator.providerDelta` prepends the epoch baseline whenever the delta does not end in a tool result.
2. The context boundary appended a stored system update after the tool result, so the delta ended in `system` and the baseline got prepended as well.

On a warm session both land after `assistant`, at an index greater than 0, and line 87 raises. An isolated hanashi test with the real Qwen tokenizer confirmed that the turn-1 shape and a plain `tool` continuation both render with the stock 0.6.2 config; the template was never the problem for those shapes.

## The fix

`UzuTurn`'s `TurnGate` now treats the session as stateful, with three starts:

- **warm**: the session already holds the epoch; only the new delta is sent. A leading system entry equal to the baseline the session holds is dropped.
- **clean**: a new epoch or a harness reset (cancel, compaction) rewound the cursor, so the delta carries the whole epoch. The session is reset and gets the leading system message plus the tool namespace developer message.
- **replay**: tools, reasoning effort, context length, or a failed turn forced a rebuild mid-epoch while the harness cursor stayed put. `TurnGate` keeps its own copy of everything the session accepted this epoch and replays it after the system and tools messages. Before this, a tool change silently dropped the conversation. Live test `U2_toolChangeMidEpochKeepsHistory` covers it.

Any non-leading system or developer text becomes a user message wrapped in `<system-reminder>`. The ordering table (`configs/ordering/default.json`) accepts `user` after every role, and the template accepts it anywhere.

The reasoning effort rides on the leading system message. Qwen's renderer maps only `disabled` and `default`, so `disabled` and Low send `disabled` (no thinking), and Medium, High and above send `default`. With `disabled`, the eval model now returns no reasoning.

## Earlier failures on the same render

These were hit while the system text was still being reshaped, and no longer occur:

- `Cannot map 'high' for 'reasoning_effort' on role 'system'`: the system role's `enable_thinking` map has only `disabled` and `default`. `UzuTurn` now sends only those two.
- `Duplicate context key: 'enable_thinking'`: set by two system messages in one render.
- `Expected one of [assistant, user] after 'user', got 'tool'`: from an experiment that folded system text into the user message; that shape is gone.

`patches/apply-uzu-qwen-template.py` (relax line 87, add effort keys, tolerate equal duplicate keys) is not needed for this fix. It stays as an option if a later template rule needs an xcframework rebuild.
