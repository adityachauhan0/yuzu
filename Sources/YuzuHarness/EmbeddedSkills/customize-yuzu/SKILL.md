---
name: customize-yuzu
description: Use when the user wants to install or change an MCP server (including DuckDuckGo), a skill, an agent, or a permission rule in Yuzu's own configuration. Not for ordinary project code.
---

# Customize Yuzu

Load this skill when the user is changing how Yuzu itself is set up — agents, skills, MCP servers, or permission rules — rather than editing application code in their project.

## Scope

- Project-level `.yuzu` configuration
- Agent definitions and permission posture
- Skill sources under the project or user skill directories
- MCP server entries in settings

## How to work in this harness

You already have `read`, `grep`, `glob`, `write`, `edit`, `bash`, `webfetch`, `skill`, and `task`. Use those on the user's project. Use `question` when you must ask them something before continuing.

When the user asks to install, remove, or list an MCP server, call the `mcp` tool. Do not edit `mcp.json` with `write`.

- List: `{"action":"list"}`
- Remove: `{"action":"remove","name":"duckduckgo"}`
- Install DuckDuckGo search: `{"action":"install","name":"duckduckgo"}`. That runs `npx -y duckduckgo-mcp-server`.
- Install any other stdio server: `{"action":"install","name":"...","command":"...","args":["..."]}`
- Install an HTTP server: `{"action":"install","name":"...","url":"https://..."}`

The user may be asked to allow the install once. After it connects, the server's tools appear on the next turn. If connection fails, the entry is still saved.

To teach Yuzu a project skill, write `.yuzu/skills/<name>/SKILL.md` with `name` and `description` frontmatter, then the instructions.

## Out of scope

- Ordinary feature work in the user's repository
- Refactors, tests, or product code unrelated to Yuzu configuration

This sentence must never appear in skill guidance baseline text.

When in doubt, ask whether the change affects Yuzu's harness behavior or only the user's app under development.
