<div align="center">

<img src=".github/assets/icon.png" width="112" alt="Yuzu" />

# Yuzu

**A local AI workspace for your Mac.**<br/>
Chat, write, and code with a model that runs entirely on your machine.

[![macOS 26.4+](https://img.shields.io/badge/macOS-26.4%2B-1B1D20?style=flat-square&logo=apple&logoColor=white)](#requirements)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-1B1D20?style=flat-square)](#requirements)
[![Swift 6](https://img.shields.io/badge/Swift-6-B9D3C4?style=flat-square&logo=swift&logoColor=1B1D20)](https://swift.org)
[![Powered by uzu](https://img.shields.io/badge/inference-uzu-B9D3C4?style=flat-square)](https://github.com/trymirai/uzu)
[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-1B1D20?style=flat-square)](LICENSE)

**[Download for Mac](https://github.com/adityachauhan0/yuzu/releases/latest/download/Yuzu.dmg)** · [Website](https://adityachauhan0.github.io/yuzu/) · [Releases](https://github.com/adityachauhan0/yuzu/releases)

<br/>

<img src=".github/assets/demo.gif" width="860" alt="Yuzu demo: switching between Cowork and Code, with the model, CPU, and RAM shown live" />

</div>

<br/>

Yuzu is a native SwiftUI app wrapped around a real agent harness. Connect it to Slack, GitHub, Linear, Notion, or any MCP server, teach it your team's workflows as skills, and let it work across your tools and your repo, asking before it acts. The model runs on your Mac, and so do the transcript and your files.

## Highlights

|   |   |
|---|---|
| 🔌 **Any MCP server** | Local (stdio) and remote (streamable HTTP) servers, with OAuth sign-in and tokens kept in the Keychain. Tools, prompts, and resources all reach the agent. Ask *“install the DuckDuckGo MCP”* and it installs one for you. |
| 🧩 **Skills** | Teach Yuzu a workflow once in a `SKILL.md`, with scripts and templates alongside. The agent loads it when a request matches, or you run it as a `/command`. |
| 🐱 **Fully local** | Inference runs on [uzu](https://github.com/trymirai/uzu) on Apple Silicon. Yuzu picks the largest Mirai-quantized chat model that fits in half your RAM and downloads it to uzu's cache on first launch. No weights ship in the app. |
| ✍️ **Cowork** | Everyday work across your tools: briefings, triage, drafts, research. Tasks run in a private sandbox folder and can run on a schedule. |
| 🧑‍💻 **Code** | Open any folder and work on it. Threads are grouped by workspace in the sidebar. |
| 🔐 **Permissions you control** | Cycle between **Workspace Read** (ask before edits and shell), **Workspace Write** (edits allowed, shell asks), and **YOLO** (no prompts). MCP tools ask before they run. The **Plan** agent can never edit or run commands. |
| 🤝 **Subagents and todos** | Hand a side quest to a subagent with its own loop, and track multi-step work in a live progress list. |
| ⚡ **Live turns** | Reasoning, text, and tool calls stream in as they happen. Replies render as Markdown with themed code blocks. |
| 📊 **Honest metrics** | Live context usage, decode tok/s (time to first token excluded), and the CPU and RAM used by the model process itself. |

## What you can do with it

MCP connects Yuzu to the tools you already use. Skills teach it how your team uses them. Put them together and a local model can do real work:

| Connect | Then ask |
|---|---|
| **Slack** | *“Summarize what I missed in #eng since yesterday and draft replies to anything that mentions me.”* |
| **GitHub** | *“Review the open PRs on this repo, check each one against our style skill, and leave a summary.”* |
| **Linear** | *“Turn the TODOs in this folder into Linear issues, tagged by area, linked to the right files.”* |
| **Sentry** | *“Pull the top crash from last night, find the code path in this repo, and propose a fix.”* |
| **Notion** | *“Write this week's release notes from merged PRs and file them in our Notion changelog.”* |
| **Web search** | *“Research three alternatives to our current queue, compare them in a table, and save it to a file.”* |

Schedule any of these from Cowork (for example, a Slack digest every weekday at 9) and Yuzu runs it on its own.

### Connect a server

Ask in any thread:

> Install the DuckDuckGo MCP server.

The agent writes the entry, connects it, and starts using it. For servers that need a token, add them under **Customize → Connectors** or in `~/Library/Application Support/Yuzu/mcp.json`:

```json
{
  "mcp_servers": {
    "slack": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-slack"],
      "env": { "SLACK_BOT_TOKEN": "xoxb-…", "SLACK_TEAM_ID": "T…" }
    },
    "github": {
      "url": "https://api.githubcopilot.com/mcp/",
      "headers": { "Authorization": "Bearer github_pat_…" }
    },
    "notion": {
      "command": "npx",
      "args": ["-y", "@notionhq/notion-mcp-server"],
      "env": { "NOTION_TOKEN": "ntn_…" }
    }
  }
}
```

Remote servers that answer with an OAuth challenge get a **Sign in** button in Connectors. Yuzu runs the browser flow with PKCE on a local loopback port and keeps the token in your Keychain. Each server's tools reach the agent as `mcp` calls, its prompts become `/commands` in the composer, and its resources can be read into context.

### Teach it a workflow

A skill is a folder with a `SKILL.md`, plus any scripts, templates, or reference files it needs:

```markdown
---
name: standup
description: Use when the user asks for a standup, a daily update, or "what did I do yesterday".
slash: true
---

1. Read my commits from the last working day with `git log --author`.
2. Read the Linear issues assigned to me that moved state.
3. Read my Slack messages in #eng and #product.
4. Write three short sections: Done, Doing, Blocked. Link every item.
5. Post it to #standup only after I approve the draft.
```

The agent sees only the name and description until a request matches, then loads the full instructions and the list of files beside it, so a skill can ship its own scripts. With `slash: true`, the skill is also a command: type `/standup` in the composer.

Skills live in `.yuzu/skills/<name>/` inside a project (shared with your team through git) or in `~/Library/Application Support/Yuzu/skills/<name>/` for personal ones. Yuzu ships with one built in, `customize-yuzu`, which lets the agent install MCP servers, write skills, and edit its own permission rules when you ask.

## How it works

```mermaid
flowchart LR
    UI["SwiftUI shell<br/>Cowork · Code · Settings"] --> Runner["SessionRunner<br/>drain loop"]
    Runner --> Store[("SQLite transcript<br/>GRDB")]
    Runner --> Tools["Tool registry<br/>+ permission gate"]
    Runner --> Model["UzuTurn"]
    Model --> Uzu["uzu engine<br/>on-device Qwen"]
    Tools --> FS["read · write · edit<br/>glob · grep · bash"]
    Tools --> Net["webfetch · MCP servers"]
    Tools --> Meta["skill · task · todo · question"]
```

Every message is written to SQLite before the next model turn, so a thread survives a crash or a relaunch. Each turn rebuilds a small, frozen baseline (project instructions, the skill list, workspace, date, MCP notes) and sends only what is new since the model last saw the session. Long threads compact themselves into a summary and keep the most recent messages verbatim.

### The pieces

| Path | What lives there |
|---|---|
| [`Sources/YuzuHarness`](Sources/YuzuHarness) | The engine: session loop, context, compaction, tools, permissions, MCP, skills, agents, schedules. No UI, no model dependency. |
| [`Sources/YuzuModel`](Sources/YuzuModel) | `UzuTurn`, the only file that imports uzu. It streams text, reasoning, and token stats back to the harness. |
| [`App/Yuzu`](App/Yuzu) | The macOS app: shell, sidebar, threads, settings, theme, and fonts. |
| [`Tests`](Tests) | Harness tests, plus live model tests behind environment flags. |

## Requirements

- An Apple Silicon Mac running **macOS 26.4** or later
- **Xcode** with the macOS 26.4 SDK
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you add or move app source files
- Free disk space for the model. The 9B model is several GB, and uzu downloads it once.

## Install

1. Download **[Yuzu.dmg](https://github.com/adityachauhan0/yuzu/releases/latest/download/Yuzu.dmg)** and drag Yuzu into Applications.
2. This build is ad-hoc signed, so macOS asks before the first open. Go to **System Settings → Privacy & Security → Open Anyway**, or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Yuzu.app
   ```
3. On first launch Yuzu downloads the model that fits your Mac, with progress in the model picker. If the download stops, click the model to try again.

## Build and run

```bash
git clone https://github.com/adityachauhan0/yuzu.git
cd yuzu

# Build the app
xcodebuild -project App/Yuzu.xcodeproj -scheme Yuzu -destination 'platform=macOS' build

# Or open it in Xcode and press ⌘R
open App/Yuzu.xcodeproj
```

The first launch downloads the advised model. After that, Yuzu starts offline.

> [!TIP]
> Added a new Swift file under `App/Yuzu`? Run `xcodegen generate` inside `App/` so the project picks it up.

## Make it yours

| What | Where |
|---|---|
| Project instructions | `YUZU.md` (or `AGENTS.md`) at the root of the folder you open |
| Project skills | `.yuzu/skills/<name>/SKILL.md` |
| Personal skills | `~/Library/Application Support/Yuzu/skills/<name>/SKILL.md` |
| MCP servers | `~/Library/Application Support/Yuzu/mcp.json`, **Customize → Connectors**, or just ask the agent |

See [What you can do with it](#what-you-can-do-with-it) for MCP and skill examples.

## Tests

```bash
# Harness tests
swift test

# App and window tests
xcodebuild -project App/Yuzu.xcodeproj -scheme Yuzu -destination 'platform=macOS' test

# Live model tests (downloads a model)
YUZU_EVAL_MODEL=1 swift test --filter LiveUzuTests
YUZU_LIVE_HARNESS_MODEL='alibaba:qwen3.5:9b:mirai:mirai-m:4' swift test --filter LiveHarnessTests
```

## Acknowledgements

- [uzu](https://github.com/trymirai/uzu) by Mirai for on-device inference
- [GRDB.swift](https://github.com/groue/GRDB.swift) for SQLite
- [OpenCode](https://github.com/anomalyco/opencode) for the harness ideas this one learned from
- [Inter](https://rsms.me/inter/), [Source Serif 4](https://github.com/adobe-fonts/source-serif), and [OpenDyslexic](https://opendyslexic.org), all under the SIL Open Font License (see [`App/Yuzu/Fonts`](App/Yuzu/Fonts))

## License

Yuzu is licensed under the [GNU AGPL-3.0](LICENSE). You can use, study, and modify it freely, as long as anything you build on it, including a hosted service, is released as open source under the same license.

<div align="center">
<br/>
<sub>Made on a Mac, for a Mac. The cat is in.</sub>
</div>
