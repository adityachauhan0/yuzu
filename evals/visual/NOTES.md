# Visual verification — `cursor/harness-architecture`

Captured **2026-10-10** on macOS (arm64). Goldens from `design/product-handoff/index.html` at 1440×900 via headless Chrome + in-page route setup. Actuals from Debug `Yuzu.app` window captures (`screencapture -l` with `CGWindow` id at 1440×900 default size). Routes that need a specific screen use launch env `YUZU_UI_ROUTE` (same names as `UITestRoute`); theme for captures uses `YUZU_UI_THEME=dark|light` (same as Settings → General). Scheduled nav still works from the sidebar in a normal session.

## Routes captured

| Route | Golden (dark/light) | Actual (dark) | Actual (light) |
| --- | --- | --- | --- |
| G1 Code home | `code-home-*.png` | `actual/code-home-dark.png` | `actual/code-home-light.png` |
| G2 Cowork new | `cowork-new-*.png` | `actual/cowork-new-dark.png` | `actual/cowork-new-light.png` |
| G3 Task + inspector | `cowork-task-*.png` | `actual/cowork-task-dark.png` | `actual/cowork-task-light.png` |
| G4 Scheduled empty | `scheduled-empty-*.png` | `actual/scheduled-empty-dark.png` | `actual/scheduled-empty-light.png` |
| G5 Customize skills | `customize-skills-*.png` | `actual/customize-skills-dark.png` | `actual/customize-skills-light.png` |
| G6 Projects / Artifacts | `cowork-projects-*.png`, `cowork-artifacts-*.png` | `actual/cowork-projects-dark.png`, `actual/cowork-artifacts-dark.png` | `actual/cowork-projects-light.png`, `actual/cowork-artifacts-light.png` |
| G7 Settings Code | `settings-code-*.png` | `actual/settings-code-dark.png` | `actual/settings-code-light.png` |
| G8 Settings General (Dark) | `settings-general-*.png` | `actual/settings-general-dark.png` | `actual/settings-general-light.png` |

### Light actuals recaptured 2026-10-10

Launch: `open -na Yuzu.app --env YUZU_UI_THEME=light --env YUZU_UI_ROUTE=<route>`.

| File | `YUZU_UI_ROUTE` |
| --- | --- |
| `code-home-light.png` | `code` |
| `cowork-task-light.png` | `coworkTask` |
| `scheduled-empty-light.png` | `coworkScheduled` |
| `cowork-projects-light.png` | `coworkProjects` |
| `cowork-artifacts-light.png` | `coworkArtifacts` |
| `settings-code-light.png` | `settingsCode` |
| `settings-general-light.png` | `settingsGeneral` |

All seven routes opened successfully; none skipped.

## G2 Cowork new — region check

**Present in both:** 42px cowork mascot + **Good {Morning\|Afternoon\|Evening}, {first name}**, composer placeholder **How can I help you today?**, composer tool row (**+** menu with **Attach a file** / **Choose a project**, model button with **High / Medium / Low** effort for the loaded model name, **No project** / workspace project bar), three ideas that fill the composer without sending, sidebar chrome.

**Still open vs golden:** SwiftUI vs HTML typography and spacing (welcome scale, composer radius, idea row art). Empty submit now toasts **Write a task to get started.** (handoff `.toast` styling); Enter sends, Shift-Enter inserts a newline.

## G4 Scheduled empty — region check

**Present in both:** title band, intro with `/schedule`, awake sentence + **Keep awake**, empty **No scheduled tasks yet.**, handoff-style stopwatch illustration (inline paths, not SF Symbol), wave divider before examples, six example cards, toolbar search / sort / **New task** menu.

**Still open vs golden:** layout density (example grid spacing, page width).

## G5 Customize skills — region check

**Present in both:** **Customize** title, tabs **Skills** / **Connectors** / **Plugins**, toolbar search / filter (**All sources**, **From Yuzu**, **From you**) / sort / **Add → Create skill**, banner **Add your first skills** + **Skills teach Yuzu how you work.**, **From Yuzu · {n}** with embedded **customize-yuzu** skill row (no Anthropic copy). Skill rows open the name/description dialog; **Create skill** uses the same dialog pattern and writes via `SkillCatalog.createProjectSkill` when submitted. Connectors / Plugins tabs show **No servers added.** / **No plugins yet.**

**Still open vs golden:** golden lists many sample skills; app shows real embedded + user skills only. Paper-plane and row styling approximate handoff CSS but are not pixel-identical.

## G1 Code home — region check (actual vs golden)

**Present in both:** cowork mascot + personalized heading, usage card with Overview/Models and All/30d/7d, six-metric grid + heatmap row, Local + folder row, code-input mascot, composer placeholder, + / Manual / model / speed **—** / High effort, sidebar traffic lights + collapse + search + mode switch + nav + Tasks heading. Light/dark actuals (recaptured 2026-10-10) load `cowork-logo(-light).svg` at 42px beside the heading and `code-input-mascot(-light).svg` at 56px over the composer (16px from the bar’s right edge); `HandoffImage` resolves SVGs from the app bundle root and rasterizes them at display size so SwiftUI no longer falls back to the sparkle placeholder or paints intrinsic 850×780 / 1448×1086 frames.

**Mismatches (structural / copy):**

- **Metric values:** golden shows sample session totals; actual reads live store (zeros / **—** when empty) — correct per spec, not a UI bug.
- **Gatsby note:** hidden at zero tokens per product spec; golden still shows the sample sentence.
- **Heatmap:** actual renders an empty 26-cell grid when the store has no activity; golden has sample level-1/2 cells.
- **Model button:** shows loaded identifier `scripted`; golden uses a longer vendor-style name (substituted in product; not forbidden in app).
- **Typography & spacing:** SwiftUI layout approximates handoff CSS but is not pixel-identical to HTML (font metrics, composer corner radius, mascot offset).
- **Sidebar:** Tasks list body is empty until a task has messages or the thread is open; golden prototype may show sample rows when seeded.

## G3 / G7 / G8 — navigation

- **Task thread:** sidebar **Task** row after activity or when the thread is active; `YUZU_UI_ROUTE=coworkTask` for capture.
- **Settings:** account **Yuzu Beta** menu → **Settings** (⌘,), or `YUZU_UI_ROUTE=settingsCode` / `settingsGeneral`; Code and General tabs use `settings-tab-Code` / `settings-tab-General`.

## G6 — brief

Empty panels match in spirit (no project / no artifacts + CTA); golden uses panel layout from HTML shell, actual uses centered serif empty state.

## Verdict

**G2 and G5** composer tools and Customize toolbar match the handoff controls in dark actuals (recaptured 2026-10-10). **G1–G8** have dark actuals; light actuals now include **code-home**, **cowork-task**, **scheduled-empty**, **cowork-projects**, **cowork-artifacts**, **settings-code**, and **settings-general** (plus earlier **cowork-new** and **customize-skills**). Harness accessibility tests **V1–V9** remain green.

## Still open (summary)

- Pixel spacing and font metrics vs handoff HTML across all routes.
- Cowork new idea-card art.
- Code home live metrics / heatmap sample parity when DB is empty (by design — do not fake).
