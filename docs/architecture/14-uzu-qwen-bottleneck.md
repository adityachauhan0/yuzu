# Why a Mirai Qwen turn dies before the first token

R2 loads `alibaba:qwen3.5:9b:mirai:mirai-m:4` and then aborts inside uzu, before the model emits any text. The log line is:

```text
Yuzu model turn failed: session("Backend(message: \"Render failed: invalid operation: System message must be at the beginning. (in chat_template:87)\")")
```

The weights are already in uzu’s cache. The checkpoint size reported on that run is 5964503835 bytes. Generation never starts. The failure is the chat template compiled into the uzu 0.6.2 binary.

## The line that throws

uzu selects the bundled Qwen 3.5 renderer for this checkpoint. The template is `crates/legacy/hanashi/configs/rendering/qwen3.5.json`. Line 87 is this raise, inside the loop over the Jinja variable `messages`:

```jinja
{%- for message in messages %}
    {%- set content = render_content(message.content, true)|trim %}
    {%- if message.role == "system" %}
        {%- if not loop.first %}
            {{- raise_exception('System message must be at the beginning.') }}
        {%- endif %}
    {%- elif message.role == "user" %}
        ...
```

`loop.first` is true only for the first element of that array. The raise runs when a message with `role == "system"` sits at any later index. A system message at index 0 does not take this branch. The running app took this branch, so the array the template walked contained a system role at an index greater than 0.

The same template, a few lines earlier, already handles a leading system message when tools are present. It does not remove that message from the array:

```jinja
{%- if tools and tools is iterable and tools is not mapping %}
    {{- '<|im_start|>system\n' }}
    ...tool list...
    {%- if messages[0].role == 'system' %}
        {%- set content = render_content(messages[0].content, false, true)|trim %}
        {%- if content %}
            {{- '\n\n' + content }}
        {%- endif %}
    {%- endif %}
    {{- '<|im_end|>\n' }}
{%- else %}
    {%- if messages[0].role == 'system' %}
        {%- set content = render_content(messages[0].content, false, true)|trim %}
        {{- '<|im_start|>system\n' + content + '<|im_end|>\n' }}
    {%- endif %}
{%- endif %}
```

Index 0 is inlined into that preamble. Every later system role still hits line 87. Qwen’s own templates for 3.6 and 3.8 have the same raise. This is the template choice tracked in [QwenLM/Qwen3.8#244](https://github.com/QwenLM/Qwen3.8/issues/244). ChatML itself allows a system turn later in the list. This copy of the template refuses one.

## What Yuzu handed uzu on the failing run

`UzuTurn.messages(for:)` builds one system message from every system and developer text in the delta, and puts that message first. Tool definitions go on a following developer message. The user turn follows that.

```177:201:Sources/YuzuModel/UzuTurn.swift
    private func messages(for request: TurnRequest, includeTools: Bool, effort: YuzuHarness.ReasoningEffort) throws -> [ChatMessage] {
        var systemParts: [String] = []
        var conversation: [StoredMessage] = []
        for message in request.delta {
            switch message.role {
            case .system, .developer:
                if !message.text.isEmpty {
                    systemParts.append(message.text)
                }
            case .user, .assistant, .tool:
                conversation.append(message)
            }
        }
        var messages: [ChatMessage] = []
        if !systemParts.isEmpty {
            messages.append(ChatMessage.system().withText(text: systemParts.joined(separator: "\n\n")))
        }
        if includeTools {
            messages.append(try toolNamespaceMessage(request.tools))
        }
        messages.append(contentsOf: try conversation.map { try chatMessage($0, effort: effort) })
        return messages
    }
```

The Qwen 3.5 rendering config gives the developer role no message body. Tool namespaces are the Jinja variable `tools`. The renderer drops a message whose body is empty (`hanashi/src/chat/hanashi/renderer/mod.rs`, the `if !rendered.message.is_empty()` check). That developer message is not an element of the array the loop walks.

`ChatSession` does not render only the new delta. `send_input` appends the input onto the session vector, then renders the whole vector (`nagare/src/chat/mod.rs`). A new session starts as an empty vector (`messages: Arc::new(Mutex::new(Vec::new()))`).

A fresh session plus the input above, after the empty developer message is dropped, is a system message at index 0 followed by the user turn. Line 86 does not fire for that shape. The process still executed line 87. The array that reached the loop had a system role after another element.

## The same template, the previous shape

Folding the system text into the user message, so the input contained no system role, got past line 87 and failed the next rule in this same render. uzu’s ordering table for this config (`configs/ordering/default.json`) allows `user` to be followed only by `assistant` or `user`. The error was:

```text
Expected one of [assistant, user] after 'user', got 'tool'
```

That table is applied in `hanashi/src/chat/hanashi/mod.rs` `encode`, before `render_messages`. A tool result is legal only after an assistant message. Removing the system role did not leave the template. It moved the failure from line 87 to that ordering check.

Two earlier failures on this same render, before the line 87 result above, were also this template’s system role:

- `Cannot map 'high' for 'reasoning_effort' on role 'system'`. The system role’s `enable_thinking` map in `qwen3.5.json` has `disabled` and `default` only. `high` is not a key. The window’s default effort is `high`.
- `Duplicate context key: 'enable_thinking'`. `enable_thinking` is one Jinja context value, not a per-message field. `insert_into_context` returns an error when the key is set twice.

## Why editing Yuzu’s message list cannot finish this

The template and the ordering table are compiled into `uzu.xcframework`. uzu’s Swift package is a binary target:

```swift
.binaryTarget(
    name: "uzu",
    url: "https://artifacts.trymirai.com/uzu-swift/releases/0.6.2.zip",
    checksum: "0013bfe9042b0859c8e6baadb8c5cd3bff81883f68efe83aad33aa8b6899f5f9"
)
```

Hanashi’s build script turns the JSON into `bundled_configs.rs` and that string is what `get_template` renders. The copy of `qwen3.5.json` in a source checkout is not the copy the app runs. `Package.swift` in this repo depends on `github.com/trymirai/uzu` from 0.6.2, which downloads that zip.

The blocker is that render. The Mirai Qwen 3.5 9B checkpoint is loaded. The turn dies at chat template line 87 because the message array the template walks contains a system role that is not its first element.
