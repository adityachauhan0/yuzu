# Theme audit (Shell + Theme)

Read-only snapshot against `App/Yuzu/Theme/Theme.swift`, `Sources/YuzuHarness/Tokens.swift`, and [16-v1-implementation.md](16-v1-implementation.md) (theme rule + §4 Chrome). Scope: `App/Yuzu/Shell/**/*.swift` and `App/Yuzu/Theme/Theme.swift`.

**Verdict:** The shell largely uses `ThemeColors` for typography and surfaces, but several V1 chrome rules are not met yet: native account menu, native settings switches, off-palette primary buttons, a combined model/effort picker on the thread, the reply cat mark, and multiple ad-hoc hex/RGB colors outside the token path.

---

## `Color(red:)`, `Color(white:)`, `Color(hex:)` outside `ThemeColors` / `Tokens`

Allowed in `Theme.swift`: `ThemeColors` and `CodeTheme` syntax previews/blocks (code highlighting is not app chrome).

| File | One-line description |
| --- | --- |
| `App/Yuzu/Shell/RootShellView.swift` | Scheduled **New task** button uses fixed RGB text/background (~#1C1C21 on ~#F0F2F2), not palette roles. |
| `App/Yuzu/Shell/RootShellView.swift` | Schedule create dialog **Create task** primary action uses the same fixed RGB pair. |
| `App/Yuzu/Shell/RootShellView.swift` | Scheduled **Keep awake** custom track uses `colors.accent` / `colors.line` and thumb `colors.text` instead of `toggleOn` / `toggleOnText`. |
| `App/Yuzu/Shell/CustomizeView.swift` | Customize **Add** dropdown trigger uses fixed RGB text/background, ignoring light/dark `ThemeColors`. |
| `App/Yuzu/Shell/SkillDialogView.swift` | Skill dialog **Save** (or equivalent primary) uses fixed RGB text/background. |
| `App/Yuzu/Shell/CodeHomeView.swift` | **Manual** label uses `Color(red: 0.89, green: 0.67, blue: 0.02)` instead of a theme role (e.g. accent/muted). |
| `App/Yuzu/Shell/SearchDialogView.swift` | Scrim, search field fill, and dialog border use raw `Color(hex: …)` and `Color.black` branches instead of `canvas` / `surface` / `line`. |
| `App/Yuzu/Shell/HandoffIllustrations.swift` | Empty-state illustration fills/strokes use local hex literals, not `ThemeColors`. |

Modal scrims (`Color.black.opacity(…)`) appear in `SettingsDialog.swift`, `RootShellView.swift`, `TaskThreadView.swift`, `SkillDialogView.swift`, and `SearchDialogView.swift`; they are not tokenized (consider `canvas` or a single shared scrim role when touching those views).

---

## `Toggle` with `.switch` (native switch)

| File | Control |
| --- | --- |
| `App/Yuzu/Shell/SettingsDialog.swift` | **Response completions** (`Toggle` + `.toggleStyle(.switch)` on General/Cowork-adjacent panel). |
| `App/Yuzu/Shell/SettingsDialog.swift` | **Memory** (`Toggle` + `.toggleStyle(.switch)` on Cowork panel). |

**Keep awake** (`RootShellView.swift`, Scheduled page): custom control, not `.switch`, but track/thumb colors do not use `toggleOn` / `toggleOnText` per §4.

No other `.switch` toggles under Shell/Theme.

---

## SwiftUI `Menu` (account, model, effort)

| File | Control |
| --- | --- |
| `App/Yuzu/Shell/SidebarView.swift` | **Account row** is a SwiftUI `Menu` (with nested `Menu("Language")`), not the custom popover required in §4. |

**Model / effort:** not SwiftUI `Menu`, but V1 requires **two** controls with appropriate popovers:

| File | Issue |
| --- | --- |
| `App/Yuzu/Shell/TaskThreadView.swift` | **Model** opens `HandoffPopover` labeled “Model and effort”; **effort** is static `Text`, not a second control. |
| `App/Yuzu/Shell/CodeHomeView.swift` | Separate **model** and **effort** buttons both toggle the same combined “Model and effort” popover. |

Other popovers (`HandoffPopover` for thread add, code add, scheduled/customize sort, etc.) are custom overlays—not account/model/effort menus.

---

## Hard-coded font/foreground colors bypassing `ThemeColors`

| File | One-line description |
| --- | --- |
| `App/Yuzu/Shell/RootShellView.swift` | Primary scheduled actions set `.foregroundStyle(Color(red:…))` instead of `text` / `onAccent`. |
| `App/Yuzu/Shell/CustomizeView.swift` | **Add** button label uses RGB foreground. |
| `App/Yuzu/Shell/SkillDialogView.swift` | Primary dialog button uses RGB foreground. |
| `App/Yuzu/Shell/CodeHomeView.swift` | **Manual** uses amber RGB foreground. |
| `App/Yuzu/Shell/SearchDialogView.swift` | Field and border colors bypass `text` / `line` / `surface` for hex branches. |

Most other Shell views consistently use `colors.text`, `muted`, `dim`, `softText`, `subtle`, `accent`, etc.

---

## Account row padding (`SidebarView`)

| File | One-line description |
| --- | --- |
| `App/Yuzu/Shell/SidebarView.swift` | Account `Menu` label has inner padding (14×10) only; no outer inset from sidebar bottom/side edges (nav uses `.padding(.horizontal, 10)`; account control is full-width flush to `colors.side`). |

§4 expects the account control inset from the bottom and sidebar edges inside a custom popover shell.

---

## Decorative cat / brand under reply (`TaskThreadView`)

| File | One-line description |
| --- | --- |
| `App/Yuzu/Shell/TaskThreadView.swift` | Last settled reply still renders `HandoffImage.coworkLogo` with `accessibilityID("thread-brand")` under the copy control; V1 removes this mark. |

Related (not under-reply): cowork/code home headers and sidebar account avatar still use the same logo asset—only the thread reply decoration is called out in V1 order #1.

---

## Rules for V1 implementers (keep existing visual language)

1. **Surfaces:** `canvas` (main), `side` (sidebar), `surface` / `surfaceHover` / `selected` (cards, inputs, hovers), `line` (borders). No new gray RGB pairs for “primary” buttons—use `accent` + `onAccent` or `text` on `surfaceHover` like the rest of the app.
2. **Typography colors:** `text`, `muted`, `dim`, `softText`, `subtle` for hierarchy; `preview` only where the handoff uses preview panels (e.g. search dialog body may stay on `preview` once borders/scrim use tokens).
3. **Switches:** Keep awake, Memory, and Response completions share one **custom** switch: track `toggleOn` when on, `line` (or documented idle track) when off; thumb/label emphasis `toggleOnText` / `text`. No `.toggleStyle(.switch)`.
4. **Account:** Replace `Menu` with `HandoffPopover` (or equivalent) listing version, Settings, Language (single checked row), Inference configuration, changelog, Learn more, Sign out; pad the control from bottom and horizontal sidebar inset to match §4.
5. **Model and effort:** Two distinct controls on thread and Code footers; each opens its own popover (or direct cycle)—do not combine into one “Model and effort” list for V1 tests.
6. **Thread chrome:** New tool/thinking/footer rows use the same font colors as existing thread prose (`softText` / `subtle` / `dim`); send/stop keep `sendIdle`, `sendIdleText`, `accent`, `onAccent`.
7. **Popovers:** Reuse `HandoffPopover` + `HandoffMenuLabel` + `HandoffPopoverRow` styling (`surface`, `line` stroke); scrims should derive from theme, not one-off hex scrims per dialog.
8. **No new literals:** Do not add `Color(red:)`, `Color(white:)`, or shell-local `Color(hex:)` for chrome; extend `ThemeColors` / `Tokens` if a handoff token is missing.
9. **Code blocks:** Syntax colors stay on `CodeTheme` in `Theme.swift`; do not mix code palette into shell controls.
10. **Copy row:** Remove `thread-brand` logo under replies; keep copy button on `colors.dim` as today.

---

## Ten worst deviations (summary)

1. Sidebar **account row** is a native SwiftUI `Menu`, explicitly forbidden in the V1 theme rule and §4.
2. Settings **Memory** and **Response completions** use native `.switch` toggles instead of the custom `toggleOn` switch.
3. Thread **model + effort** are not two independent controls; effort is read-only text and model opens a combined popover.
4. Code home **model** and **effort** buttons share one combined popover, not separate model vs effort UX.
5. **thread-brand** cowork logo still appears under the last assistant reply; V1 requires copy without the cat mark.
6. Multiple **primary CTAs** (Scheduled New task, schedule Create, Customize Add, Skill save) hard-code light-gray RGB and ignore dark/light `ThemeColors`.
7. **SearchDialogView** scrim, field background, and border use bespoke hex colors instead of `canvas` / `surface` / `line`.
8. Scheduled **Keep awake** switch styling uses `accent`/`line`/`text`, not the mandated `toggleOn` / `toggleOnText` pair.
9. **Account button** lacks bottom/sidebar inset padding specified for the custom account popover chrome.
10. **Code Manual** mode label uses a fixed amber RGB, breaking themed foreground rules.
