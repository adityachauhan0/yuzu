# Agents

An agent is a named bundle of instructions, permission rules, and a step limit. It is not a second model. OpenCode agents can point at a different provider model. Yuzu has one loaded uzu model per app. Switching weights is an engine operation (eject, load), and it starts a new context epoch because the warm cache is gone. An agent switch does not do that.

## Document

```text
id            "build" | "plan" | user-defined
mode          primary | subagent | all
system        optional text appended into the epoch baseline
description   shown in the agent picker; subagents are chosen by the parent model
steps         optional provider-turn budget per user prompt
permissions   ruleset, see Permissions
hidden        omit from the picker
```

`mode: primary` appears in the picker. `mode: subagent` is only started by the task tool. `mode: all` can do both.

Shipped agents: `build` and `plan`, with the rules in [Permissions](05-permissions.md). `build` is the default. Neither sets `steps` until we have measured a local model looping; the field exists so a user agent can set it.

## Switching

The session stores the current agent id. A switch applies on the next provider turn. It does not cancel the turn already inside uzu. Skill guidance is re-rendered at the next boundary. A pending permission keeps the agent that issued the call.

The agent’s `system` text is part of the baseline. Changing it starts a new epoch (reset and replay), because the baseline is immutable inside an epoch. Permission-only and skill-list changes do not.

## Subagents

Not in the first working slice. The shape, so the session loop does not grow a special case later:

The `task` tool is a builtin. Input is `{ agent, prompt }`. Permission action `task`, resource the agent id. Execute runs a child drain:

- new session id, same project, `mode` must allow subagent
- its own history and epoch
- the same `UzuTurn` and the same loaded model
- parent drain waits; we do not overlap two uzu turns
- child tool list is materialized from the child agent’s rules, which is how `plan` stays read-only when used as a subagent
- the child’s final assistant text is the tool result

The parent’s step counter does not increment for the child’s internal turns. One `task` call is one parent step.

## Model identity in the baseline

The workspace source includes the loaded model identifier so the transcript still makes sense after a reload. Changing model ejects the chat instance, starts a new epoch, and replays projected history into a fresh session. Reasoning text from the old model is kept as ordinary assistant text. Any opaque reasoning signature uzu attached is dropped on replay.
