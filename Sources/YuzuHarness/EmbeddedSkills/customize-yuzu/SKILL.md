---
name: customize-yuzu
description: Use when editing Yuzu's own configuration (agents, skills, MCP servers, permission rules), not the user's project.
---

# Customize Yuzu

Load this skill when the user is changing how Yuzu itself is set up — agents, skills, MCP servers, or permission rules — rather than editing application code in their project.

## Scope

- Project-level `.yuzu` configuration
- Agent definitions and permission posture
- Skill sources under the project or user skill directories
- MCP server entries in settings

## Out of scope

- Ordinary feature work in the user's repository
- Refactors, tests, or product code unrelated to Yuzu configuration

This sentence must never appear in skill guidance baseline text.

When in doubt, ask whether the change affects Yuzu's harness behavior or only the user's app under development.
