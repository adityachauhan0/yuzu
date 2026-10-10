# Visual verification — `cursor/harness-architecture`

Captured **2026-10-10** on macOS (arm64). Goldens from `design/product-handoff/index.html` at 1440×900 via headless Chrome + in-page route setup. Actuals from Debug `Yuzu.app` window captures (`screencapture -l <windowid>`). Routes that need a specific screen use launch env `YUZU_UI_ROUTE` (same names as `UITestRoute`); theme for captures uses `YUZU_UI_THEME=dark|light` (same as Settings → General). Scheduled nav still works from the sidebar in a normal session.

## Routes captured

| Route | Golden (dark/light) | Actual (dark) | Actual (light) |
| --- | --- | --- | --- |
| G1 Code home | `code-home-*.png` | `actual/code-home-dark.png` | — |
| G2 Cowork new | `cowork-new-*.png` | `actual/cowork-new-dark.png` | `actual/cowork-new-light.png` |
| G3 Task + inspector | `cowork-task-*.png` | `actual/cowork-task-dark.png` | — |
| G4 Scheduled empty | `scheduled-empty-*.png` | `actual/scheduled-empty-dark.png` | — |
| G5 Customize skills | `customize-skills-*.png` | `actual/customize-skills-dark.png` | `actual/customize-skills-light.png` |
| G6 Projects / Artifacts | `cowork-projects-*.png`, `cowork-artifacts-*.png` | `actual/cowork-projects-dark.png`, `actual/cowork-artifacts-dark.png` | — |
| G7 Settings Code | `settings-code-*.png` | `actual/settings-code-dark.png` | — |
| G8 Settings General (Dark) | `settings-general-*.png` | `actual/settings-general-dark.png` | — |

## G2 Cowork new — region check

**Present in both:** 42px cowork mascot + **Good {Morning\|Afternoon\|Evening}, {first name}** (live time-of-day + Mac account name), composer placeholder **How can I help you today?**, three ideas (**Send me a daily briefing**, **Organize my inbox**, **Customize Cowork for me**) that fill the composer without sending, sidebar chrome.

**Still open vs golden:** SwiftUI vs HTML typography and spacing (welcome scale, composer radius, idea row layout). Full composer tool row (+ / model / project) not yet mirrored on Cowork new.

## G4 Scheduled empty — region check

**Present in both:** title band, intro with `/schedule`, awake sentence + **Keep awake**, empty **No scheduled tasks yet.**, handoff-style stopwatch illustration (inline paths, not SF Symbol), wave divider before examples, six example cards, toolbar search / sort / **New task** menu.

**Still open vs golden:** layout density (example grid spacing, page width), scheduled-empty-light actual not captured.

## G5 Customize skills — region check

**Present in both:** **Customize** title, tabs **Skills** / **Connectors** / **Plugins**, banner **Add your first skills** + **Skills teach Yuzu how you work.**, **From Yuzu · 1** with embedded **customize-yuzu** skill row (no Anthropic copy). Connectors / Plugins tabs show **No servers added.** / **No plugins yet.**

**Still open vs golden:** golden lists many sample skills; app shows real embedded + user skills only. Toolbar search / filter / sort / **Add** not yet built. Paper-plane and row styling approximate handoff CSS but are not pixel-identical.

## G1 Code home — region check (actual vs golden)

**Present in both:** cowork mascot + personalized heading, usage card with Overview/Models and All/30d/7d, six-metric grid + heatmap row, Local + folder row, code-input mascot, composer placeholder, + / Manual / model / speed **—** / High effort, sidebar traffic lights + collapse + search + mode switch + nav + Tasks heading.

**Mismatches (structural / copy / metrics):**

- **Metric values:** golden shows sample session totals; actual reads live store zeros and **—** placeholders (correct for empty DB, different from golden PNG).
- **Gatsby note:** hidden at zero tokens per product spec; golden still shows the sample sentence.
- **Heatmap:** actual renders an empty 26-cell grid; golden has level-1/2 cells on three days.
- **Model button:** shows loaded identifier `scripted`; golden uses a longer vendor-style name (substituted in product; not forbidden in app).
- **Typography & spacing:** SwiftUI layout approximates handoff CSS but is not pixel-identical to HTML (font metrics, composer corner radius, mascot offset).
- **Sidebar:** Tasks list body is empty until a task has messages or the thread is open; golden prototype may show sample rows when seeded.

## G3 / G7 / G8 — navigation

- **Task thread:** sidebar **Task** row after activity or when the thread is active; `YUZU_UI_ROUTE=coworkTask` for capture.
- **Settings:** account **Yuzu Beta** menu → **Settings** (⌘,), or `YUZU_UI_ROUTE=settingsCode` / `settingsGeneral`; Code and General tabs use `settings-tab-Code` / `settings-tab-General`.

## G6 — brief

Empty panels match in spirit (no project / no artifacts + CTA); golden uses panel layout from HTML shell, actual uses centered serif empty state.

## Verdict

**G2, G4, G5, G1, G3, G7, and G8** cover the required regions in dark theme with in-app navigation or launch routes; **G2 and G5** also have light actuals via `YUZU_UI_THEME=light`. **Pixel-perfect sign-off is still not met** — SwiftUI vs HTML typography/spacing, remaining light actuals for other routes, golden sample metrics/heatmap, and Cowork new composer tool row. Harness accessibility tests (V1–V8) remain green.

## Still open (summary)

- Light-theme `actual/*-light.png` for routes beyond G2 and G5 (and scheduled empty).
- Pixel spacing and font metrics vs handoff HTML across all routes.
- Cowork new composer tools (+ / model / project bar) and idea-card art.
- Customize toolbar (search, filter, sort, Add) and skill detail dialog.
- Code home live metrics / heatmap sample parity when DB is empty.
