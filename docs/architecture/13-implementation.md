# Implementation spec

> **For agentic workers:** Implement one slice at a time. A slice is done only when every eval listed for it passes. Do not start the next slice on a red eval.

**Goal:** A Mac app whose window matches the handoff and whose agent loop matches the architecture, with uzu used only as the model turn.

**Architecture:** SwiftPM library `YuzuHarness` holds the loop, tools, permissions, skills, MCP, and store. It depends on a `ModelTurn` protocol. `UzuTurn` is the only adopter that imports `Uzu`. The app target draws the handoff and sends the commands in [Client](10-client.md). Evals drive `YuzuHarness` with `ScriptedTurn` so the loop is proven without a model. One live eval loads uzu.

**Tech stack:** Swift 6, macOS 26.4, Apple silicon, SwiftUI, SQLite (GRDB), the `Uzu` package at 0.6.2 from `https://github.com/trymirai/uzu.git`.

## Global constraints

- One loaded uzu model. Two drains never call `reply` at the same time.
- No `addTool` and no `addForeignTool` unless eval `U1` fails and the fallback in [Uzu boundary](09-uzu-boundary.md) is recorded in `docs/architecture/spike-result.md`.
- `toolTurnLimit` is 0 on every harness turn.
- SQLite is the record. The uzu session is a cache.
- UI copy follows [UI](12-ui.md). The strings in eval `V1` must not appear.
- Sidebar 256, content max 806, ease `cubic-bezier(0.2, 0.8, 0.2, 1)`, hover 180ms, drawer 220ms.
- Tool names match `^[A-Za-z][A-Za-z0-9_-]{0,63}$`.

## Layout

```text
Package.swift                 YuzuHarness library + YuzuHarnessTests
App/Yuzu.xcodeproj            app target, links YuzuHarness and Uzu
App/Yuzu/Shell/               SwiftUI. One file per handoff page.
App/Yuzu/Theme/Tokens.swift   both palettes, copied from the handoff CSS
Sources/YuzuHarness/Turn.swift
Sources/YuzuHarness/Store.swift
Sources/YuzuHarness/SessionRunner.swift
Sources/YuzuHarness/Permission.swift
Sources/YuzuHarness/ToolRegistry.swift
Sources/YuzuHarness/Tools/    Read, Write, Edit, Glob, Grep, Bash, Skill
Sources/YuzuHarness/Context.swift
Sources/YuzuHarness/Compaction.swift
Sources/YuzuHarness/Skills.swift
Sources/YuzuHarness/MCP.swift
Sources/YuzuHarness/Agents.swift
Sources/YuzuModel/UzuTurn.swift
```

The app never imports `Uzu`. `YuzuHarness` never imports `Uzu`.

## Interfaces

These names are the contract. Evals call them. Later slices do not rename them.

```swift
public struct TurnRequest: Sendable {
    public var epochID: String
    public var delta: [StoredMessage]
    public var tools: [ToolDefinition]
    public var toolTurnLimit: UInt32          // harness always sends 0
    public var reasoningEffort: ReasoningEffort
    public var contextLength: Int
}

public enum TurnEvent: Sendable {
    case text(String)
    case reasoning(String)
    case finished(AssistantTurn)
}

public struct AssistantTurn: Sendable, Equatable {
    public var text: String
    public var reasoning: String
    public var toolCalls: [ToolCall]
    public var outputTokens: Int?
}

public struct ToolCall: Sendable, Equatable {
    public var id: String
    public var name: String
    public var arguments: JSONValue
}

public protocol ModelTurn: Sendable {
    func complete(_ request: TurnRequest) -> AsyncThrowingStream<TurnEvent, Error>
    func reset(epochID: String)
}

public enum Delivery: Sendable { case steer, queue }

public protocol HarnessClient: Sendable {
    func prompt(_ text: String, delivery: Delivery) async
    func cancel() async
    func replyPermission(_ id: String, _ reply: PermissionReply) async
    func setAgent(_ id: String) async
}

public enum PermissionReply: Sendable { case once, always, reject }

public struct PermissionRule: Sendable, Equatable {
    public var action: String
    public var resource: String
    public var effect: PermissionEffect   // allow, deny, ask
}
```

`SessionRunner.run` reads the store, calls `ModelTurn`, settles tools, and writes messages back. `ScriptedTurn` in tests returns a fixed list of `AssistantTurn` values, one per `complete` call.

## Visual verification

`V0`–`V8` read the accessibility tree and color tokens. They do not look at the window. A slice that draws UI is not done until the window has been captured and compared to the handoff.

Two captures, same routes:

1. **Golden.** The handoff is HTML. Open `design/product-handoff/index.html` in a browser at 1440×900, dark, then light. Screenshot each route below. Save under `design/product-handoff/golden/<route>-<theme>.png`. These files are the visual source. Regenerate them only when the handoff changes.
2. **Actual.** The app is a native window. Browser QA cannot see it. Drive Yuzu with computer use: launch the app, capture the window, click through the route, capture again. Save under `evals/visual/actual/<route>-<theme>.png` and keep the accessibility snapshot from that capture next to it.

Computer use is the visual gate, not a fallback. Aside and the IDE browser are only for producing the golden PNGs from the HTML prototype.

A route passes when all three are true:

- The actual PNG shows the same regions as the golden PNG: sidebar, mode switch, the page’s heading, the composer or the empty state, and the settings sheet when that route opens it. Judged by looking at the two images, not by a pixel diff. SwiftUI will not match HTML antialiasing, so a bit-exact diff is not the pass.
- Measured frames from the accessibility snapshot: sidebar width 256 at 1440 wide, content column at most 806, inspector beside the thread at 1440 and overlaid at 1100.
- `V1` strings are absent in the captured image, not only in the tree.

Routes, one dark and one light capture each:

| Id | Route |
| --- | --- |
| G1 | Code home, speed `—`, no sample metrics |
| G2 | Cowork new task, ideas, empty composer |
| G3 | Task thread with the disclaimer and inspector |
| G4 | Scheduled empty, including the six examples |
| G5 | Customize skills, Yuzu banner |
| G6 | Projects and Artifacts empty panels |
| G7 | Settings, Code tab, heading Code appearance |
| G8 | Settings, General, theme control with Dark pressed |

During a UI slice, capture the route you touched before calling the slice done. Do not save the screenshots for the end. If the actual image and the golden image disagree, the slice is red even when `swift test` is green.

## How evals run

```bash
swift test --filter 'YuzuHarnessTests'
```

That is the gate for every slice that does not need a window or a model. It must pass with no network and no uzu binary call.

```bash
YUZU_EVAL_MODEL=1 swift test --filter 'LiveUzuTests'
```

`LiveUzuTests` skip unless `YUZU_EVAL_MODEL=1`. CI without a model runs the skip as a pass of the skip, and does not count them toward the slice gate. A human runs them once per uzu version before a release.

```bash
xcodebuild test -scheme Yuzu -destination 'platform=macOS,arch=arm64'
```

UI evals live here. They build the SwiftUI tree offscreen. They do not screenshot-diff the HTML prototype. They assert tokens, strings, and accessibility identifiers that match the handoff’s element ids.

An eval id below is the XCTest method name. A slice exits only when its ids are green.

## Slice 0 — packages and tokens

No product behavior. `swift test` runs and reports zero tests. `Tokens.dark.canvas` is `#1B1D20` and `Tokens.light.canvas` is `#F3F5F2`. The other roles in the handoff’s color table match the same way: side, surface, surfaceHover, selected, line, lineSoft, text, muted, dim, accent, focus.

**Exit:** `V0_tokensMatchHandoff`.

## Slice 1 — model-turn spike

`UzuTurn.complete` sends one developer message from `withToolNamespaces`, namespace name `yuzu`, and does not call `addTool` or `addForeignTool`.

**U1_unregisteredToolCallReturns** (`YUZU_EVAL_MODEL=1`). Prompt tells the model to call `echo` with `{"text":"ping"}`. Pass: `toolCalls` contains that name and those arguments, and the process did not register a foreign tool.

**U1b_toolResultProducesAnswer** (`YUZU_EVAL_MODEL=1`). Second `complete` sends a `toolCallResult` whose text is `pong`. Pass: `finished.text` contains `pong`, and `toolCalls` is empty.

If `U1` fails, stop. Write `docs/architecture/spike-result.md` with the observed behavior and switch the implementation note to the `ForeignTool` fallback. Do not write slice 2 against a guess.

## Slice 2 — drain and read-only tools

Store tables: `sessions`, `messages`, `inbox`. `ScriptedTurn` is the model.

**L1_promptStaysInInboxUntilPromotion.** `prompt("hi", .queue)` then crash the runner before `complete`. Pass: inbox has the row, messages has no user row.

**L2_textOnlyTurnCompletes.** Script returns text `done` and no tool calls. Pass: status `idle`, one user message, one assistant message `done`.

**L3_toolRoundTrip.** Script first returns a `read` call for `note.txt`, then text `saw it`. Workspace contains `note.txt` = `hello`. Pass: assistant activity is recorded, tool result contains `hello`, final text is `saw it`, and the second `TurnRequest.delta` is only the tool result (the first request’s messages are not repeated).

**L4_unknownToolIsAResult.** Script calls `nope`. Pass: drain reaches `idle`, tool message contains `Unknown tool`, no thrown error.

**L5_staleTool.** Materialize without `read`, script calls `read`. Pass: result contains `Stale tool call`.

**L6_singleCallWhenUnsupported.** Model capability `supportsMultipleToolCalls == false` and the script returns two calls. Pass: one result is stored, the second call is absent from the assistant row.

**L7_cancelDropsBareToolCall.** Script starts a tool call, `cancel()` before settle. Pass: that assistant row is gone, inbox is unchanged, next `complete` is preceded by `reset`.

**L8_resumeSettlesDanglingCall.** Store an assistant `read` with no result, then `run`. Pass: the tool runs before any `complete`.

**L9_steerResetsStepOnce.** Agent `steps` is 2. During a tool settle, steer a new prompt. Pass: the step counter is 1 after that boundary, not 0 and not 2.

**L10_queueWaitsUntilIdle.** Queue a second prompt while the first drain still has a tool call pending. Pass: the second user message appears only after the first assistant text with no tool calls.

**T1_readRejectsEscape.** `read` of `../outside.txt`. Pass: tool error, file not read.

**T2_globAndGrepStayInsideProject.** Files inside and outside the project. Pass: names and matches are only inside.

**Exit:** L1–L10, T1, T2. The task thread in the app shows streamed text and an activity line. That is manual until slice UI, then `V2`.

## Slice 3 — permissions

**P1_lastMatchWins.** Rules ask, then allow, then deny for the same action and resource. Pass: effect is deny.

**P2_defaultIsAsk.** Empty ruleset. Pass: effect is ask.

**P3_unknownAgentDeniesAll.** Pass: `edit` on `*` is deny.

**P4_buildAsksForEdit.** Agent `build`. Pass: `read` allows, `edit` asks, `bash` asks.

**P5_planDeniesEditAndBash.** Pass: both deny, `read` allows. A saved allow for `edit` does not override the deny.

**P6_onceDoesNotSave.** Reply `once`. Pass: the tool runs, `permission_rules` is unchanged.

**P7_alwaysSaves.** Reply `always` for `edit` on `src/a.swift`. Pass: a later `edit` on that path allows with no ask.

**P8_rejectContinues.** Reply `reject`. Pass: tool result says the call was denied, drain continues, script’s next text is stored.

**P9_denySkipsUI.** Plan agent, script calls `edit`. Pass: no `permission.asked` event, tool result is a denial.

**P10_manualToggle.** Manual pressed: `edit` and `bash` ask. Manual unpressed: `edit` allows, `bash` still asks.

**Exit:** P1–P10.

## Slice 4 — context

**C1_baselineFrozen.** First turn stores the epoch baseline. Second turn’s system text equals that stored string.

**C2_yuzuMdBeatsAgentsMd.** Both files exist. Pass: baseline contains `YUZU.md` body and not the `AGENTS.md` body.

**C3_agentsMdWhenYuzuMissing.** Pass: baseline contains `AGENTS.md`.

**C4_changeBecomesOneSystemMessage.** Rewrite `YUZU.md` between turns. Pass: exactly one new mid-conversation system message, snapshot updated, baseline text unchanged.

**C5_unavailableSourceDoesNotClobber.** Loader fails. Pass: previous value remains, no new system message.

**C6_firstTurnBlocksWhenBaselineUnavailable.** Instructions loader fails before the first turn. Pass: inbox row still pending, no assistant message.

**Exit:** C1–C6.

## Slice 5 — write, edit, bash

**T3_editRequiresOneMatch.** File contains the needle twice. Pass: error, file unchanged.

**T4_editReplacesOne.** One match. Pass: file updated, result text says the replacement.

**T5_writeCreatesFile.** Pass: file exists with the body.

**T6_bashCwdIsProject.** `pwd`. Pass: stdout is the project path.

**T7_bashTimesOut.** `sleep 30` with timeout 1s. Pass: tool error, drain still alive.

**T8_outputCapWritesFile.** Tool returns 10_000 characters. Pass: model-visible text is capped, full text is under Application Support `tool-output/<session>/<call-id>`, and the visible text contains that path.

**Exit:** T3–T8, and P4 still green.

## Slice 6 — skills

**S1_guidanceListsNameNotBody.** Embedded skill `customize-yuzu` with a long body. Pass: baseline contains the name and description, and does not contain a unique sentence that exists only in the body.

**S2_skillToolReturnsBody.** Call `skill` with that name. Pass: result contains the body and the skill directory.

**S3_deniedSkillOmitted.** Agent denies `skill` on `customize-yuzu`. Pass: guidance omits it, and the tool is absent from `materialize`.

**S4_createSkillWritesProjectFile.** Create with name `demo` and a description. Pass: `<project>/.yuzu/skills/demo/SKILL.md` exists with that frontmatter, and the next guidance lists `demo`.

**S5_duplicateNameProjectWins.** Same name embedded and in the project. Pass: the project body is the one `skill` returns.

**Exit:** S1–S5.

## Slice 7 — MCP stdio

A test double speaks MCP stdio: `initialize`, `tools/list` with one tool `ping`, `tools/call` returns `pong`.

**M1_registersSanitizedName.** Pass: materialized name is `mcp_test_ping`, permission action `mcp:test`.

**M2_askBeforeCall.** Build agent. Pass: `permission.asked` fires, and `tools/call` is not sent until `once`.

**M3_disconnectIsStale.** Disconnect, then a script calls the old name. Pass: `Stale tool call`, and the name is gone from the next materialize.

**M4_instructionsAreAContextSource.** Server instructions `be brief`. Pass: the next boundary’s system update contains `be brief`.

**M5_httpStaticHeader.** Same server over streamable HTTP with a bearer header. Pass: M1’s name appears. OAuth is not this slice.

**Exit:** M1–M5.

## Slice 8 — compaction

Context budget in the test is 1_000 tokens. Buffer and keep use the production ratios scaled down: buffer 200, keep 100, so the test does not need a real window. Production constants stay 20_000 and 8_000. The test injects the small budget on the session.

**K1_overflowRunsSummaryTurn.** History larger than the budget. Pass: one `complete` whose tools array is empty and whose delta contains the summary instruction, then a new epoch id.

**K2_recentTailSurvives.** A unique token `KEEPME` is in the last message, `DROPME` is only in the head. Pass: projected history after compaction contains the summary and `KEEPME`, and does not contain `DROPME` as a raw message.

**K3_replayAfterReset.** After compaction, the next real turn’s first request follows a `reset`, and the replay starts with the new baseline. Pass: `ScriptedTurn.resetEpochs` contains the new id.

**K4_summaryMustCarryFacts.** The scripted summary omits `DROPME`. The eval’s summary script is required to include facts the harness passed in. Pass: the compaction prompt contains `DROPME`. This checks the prompt, not the model.

**Exit:** K1–K4. Live check, not a unit eval: with `YUZU_EVAL_MODEL=1`, a session that overflowed still answers with the fact that lived only in the dropped head. Record it in the spike notes. It is not required for `swift test`.

## Slice 9 — MCP rest and subagents

**M6_promptBecomesUserMessage.** MCP prompt `hello` returns text `wave`. Invoking it admits a user message `wave`.

**M7_readResource.** Server exposes `file://note`. Tool `read_resource` returns the body. It is materialized only when a connected server has resources.

**M8_oauthNeedsAuthStatus.** HTTP server that returns 401 and an auth challenge. Pass: status `needs_auth`, no tool registered. The browser step is manual.

**A1_taskRunsChildOnSameLock.** Parent script calls `task` for agent `plan` with prompt `look`. Child script returns text `looked`. Pass: parent tool result is `looked`, and the two `complete` calls never overlap in time.

**A2_planChildCannotEdit.** Child script calls `edit`. Pass: denial, parent still receives the child’s final text.

**A3_parentStepsIgnoreChildTurns.** Parent `steps` is 3. Child takes 5 turns. Pass: parent step count increased by 1.

**Exit:** M6–M8, A1–A3.

## Slice 10 — window

The shell uses the handoff’s accessibility identifiers: `sidebar`, `mode-switch` buttons Cowork and Code, nav buttons New, Projects, Artifacts, Scheduled, Customize, `code-view`, `home`, `task-view`, `settings-dialog`.

**V1_forbiddenCopyAbsent.** Render every page and both themes. Pass: the tree contains none of `Claude Code`, `Anthropic`, `GPT 6 Luna`, `Claude Opus`, `graph-engineering`, `tldraw`, `adityachauhan`, `not shown in the supplied reference`, `were not provided in the reference`.

**V2_disclaimerExact.** Task thread contains `Yuzu is on-device AI. its not the best. Please double check responses.`

**V3_codeTabShowsAppearance.** Open Settings, activate Code. Pass: heading `Code appearance` is visible, and the placeholder heading for a missing section is not.

**V4_emptyStates.** No sessions and no project. Pass: Artifacts shows `No artifacts yet`, Projects shows `No project yet`, skills banner contains `Skills teach Yuzu how you work.`, speed label is `—`.

**V5_darkAndLightTokens.** Both themes. Pass: canvas, text, and accent resolve to the hex values in `V0`.

**V6_reducedMotion.** `accessibilityReduceMotion` true. Pass: drawer and hover animations report duration 0.

**V7_inspectorOverlaysNarrow.** Width 1100. Pass: inspector is an overlay. Width 1400. Pass: inspector is beside the thread.

**V8_manualAndLocal.** Code footer contains `Local` and `Manual`. `Local` is selected. Pressing `Manual` flips the permission posture asserted by `P10`.

**Exit:** V0–V8, and G1–G8 captured against the running window in both themes. The harness suite is still green. A token test does not substitute for a missing capture.

## Slice exit table

| Slice | Evals that must be green |
| --- | --- |
| 0 | V0 |
| 1 | U1, U1b, or a written fallback before any later slice |
| 2 | L1–L10, T1, T2 |
| 3 | P1–P10 |
| 4 | C1–C6 |
| 5 | T3–T8 |
| 6 | S1–S5 |
| 7 | M1–M5 |
| 8 | K1–K4 |
| 9 | M6–M8, A1–A3 |
| 10 | V1–V8 and G1–G8 looked at against the golden PNGs |

A release build is correct when slices 0 through 10 are green, `U1` and `U1b` were run against uzu 0.6.2 on this machine, and G1–G8 have been looked at against the golden PNGs in both themes. `V1` being green is not that look.

## Reality evals

The suites above can all be green while the window still runs `ScriptedTurn`. That score is not a harness. R0–R2 are the correction. They do not skip.

| Id | Where | Pass | What does not count |
| --- | --- | --- | --- |
| R0 | `YuzuHarnessTests` | `ScriptedTurn.backing` is `.scripted`, and a canned complete does not contain a nonce that exists only in a file | A green R0. It only locks the stand-in. |
| R1 | `YuzuTests` | `AppModel.makeForLaunch()` installs `YuzuModel.UzuTurn` with backing `.uzu` | The button text changing away from `scripted`. A `usesLiveEngine` flag. |
| R2 | `YuzuTests` | After R1, a prompt that does not contain a random nonce still gets that nonce back, and the transcript shows a `read` of `secret.txt` | Skipping when the model is missing. Echoing the prompt. Flipping `ScriptedTurn.backing` to `.uzu` (R0 fails). |

R1 and R2 are red until the window's launch path loads uzu. Making them skip so the suite stays green is a failed eval.

## Out of these evals

Plugin installation, a second loaded model, and cloud environments. They are not in the window. An implementation that adds them fails `V1` review even if the tests are green.
