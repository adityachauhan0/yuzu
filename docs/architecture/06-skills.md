# Skills

A skill is a markdown body plus a name and a description. The model sees the description in the system context. It sees the body only after it calls the `skill` tool. That split is the whole design. Stuffing every skill into the baseline would burn the window of a local model.

## Sources

A source is one of:

- **directory** — a folder on disk
- **url** — downloaded into the app support skill cache, then treated as a directory
- **embedded** — markdown compiled into the app

Shipped directories, if they exist:

- `<project>/.yuzu/skills/`
- `~/Library/Application Support/Yuzu/skills/`

Discovery walks `SKILL.md` files and top-level `*.md`. Frontmatter is YAML with optional `name`, `description`, and `slash`. The name is the frontmatter name, or the file’s basename when the file sits directly in the source root. A `SKILL.md` in a subfolder must set `name`. Duplicate names: later source wins. Embedded sources register first, user directories next, project last.

`slash: true` also surfaces the skill as a composer command that admits a prompt whose text is the skill body. The model does not have to call the tool in that case. The normal path is still the tool.

## Guidance source

`core/skill-guidance` lists only skills the current agent is allowed to use: `evaluate("skill", skill.name, agent.permissions)` is not `deny`. Each entry is name and description, sorted by name. The rendered text says to call the `skill` tool when a task matches. An empty list still renders “no skills are currently available” unless the agent denies `skill` on `*`, in which case the source is empty and the tool is not materialized.

When the list changes, the next boundary writes one mid-conversation system message: the new list supersedes the old one. See [Context](03-context.md).

## The tool

Name `skill`. Input is `{ name }`. Permission action is `skill`, resource is the skill name.

On success the model output is:

```text
<skill_content name="...">
# Skill: ...
<body>
Base directory: <directory of the file>
<skill_files> up to 10 sibling paths </skill_files>
</skill_content>
```

The body is the markdown after frontmatter. Relative paths in the skill are relative to that directory. The file list is a sample, not a promise that those files were read. The model uses `read` for them, and `read` goes through permissions again.

Failure to find or read the skill is a tool error, not a thrown drain failure.

## First embedded skill

Ship one embedded skill, `customize-yuzu`, whose description says to use it only when the user is editing Yuzu’s own configuration: agents, skills, MCP servers, permission rules. Not when they are editing their project. Same idea as OpenCode’s `customize-opencode` skill.
