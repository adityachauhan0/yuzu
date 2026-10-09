# MCP

MCP servers are child processes or HTTP endpoints. Their tools join the same registry as builtins. The harness does not grow a second tool loop for them.

## Config

A server entry is a name plus a transport:

- **stdio** — command, args, env, cwd defaulting to the project
- **http** — URL, streamable HTTP, optional headers

Stored in `mcp_servers`. Disabled entries stay in the list and are not connected.

## Status

Each server is one of: `connected`, `disabled`, `failed` (with an error string), `needs_auth`, `needs_client_registration`. The UI lists status and can connect, disconnect, and start OAuth.

OAuth is for remote HTTP servers. The flow stores tokens in the keychain, opens the authorization URL in the browser, and finishes on a loopback redirect. Stdio servers do not use it. Until the redirect listener exists, remote servers can still connect with a static bearer header.

Connect timeout defaults to 30 seconds.

## What we take from a server

On connect, and whenever the server notifies that tools changed:

- **Tools.** Convert each MCP tool’s JSON schema into a `ToolFunction`. Register it as `mcp_<server>_<tool>` after sanitizing to the tool name grammar. The permission action is `mcp:<server>`, resource is the tool name. Default effect is ask, from the agent rules.
- **Instructions.** If the server provides them, they feed `core/mcp-instructions`. A connect or disconnect therefore changes a context source and is admitted at the next boundary.
- **Prompts.** Listed as composer slash commands. Invoking one calls `prompts/get` and admits the returned text as a user message. They are not model tools.
- **Resources.** Not dumped into context. A builtin `read_resource` tool, permission action `mcp:<server>`, takes a URI and calls `resources/read`. Materialize it only when at least one server is connected and exposes resources.

Executing an MCP tool is a registry settle that calls `tools/call` on that client with the decoded arguments and the server’s timeout. The result is mapped to text content. A transport error is a tool error string so the drain continues.

## Lifecycle

Connecting is explicit (the user enables a server, or the project config says it should start with the session). Tool-list changes unregister the old names and register the new ones. In-flight calls keep the settle closure from the turn that advertised them; a removed tool returns `Stale tool call` if the model still names it.

Quitting the app disconnects every client and rejects in-flight MCP calls as tool errors.

## What we do not do

No MCP sampling (the server asking our model to complete). The local model is ours. A server that requires sampling gets a failed status with that reason. No roots protocol beyond telling the server the project path at initialize.
