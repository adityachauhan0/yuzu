# Visual verification — `cursor/harness-architecture`

Captured **2026-10-10** on macOS (arm64). Goldens from `design/product-handoff/index.html` at 1440×900 via headless Chrome + in-page route setup. Actuals from Debug `Yuzu.app` window captures (`screencapture -l <windowid>`). Routes that need a specific screen use launch env `YUZU_UI_ROUTE` (same names as `UITestRoute`); Scheduled nav still works from the sidebar in a normal session.

## Routes captured

| Route | Golden (dark/light) | Actual (dark) |
| --- | --- | --- |
| G1 Code home | `code-home-*.png` | `actual/code-home-dark.png` |
| G2 Cowork new | `cowork-new-*.png` | `actual/cowork-new-dark.png` |
| G3 Task + inspector | `cowork-task-*.png` | `actual/cowork-task-dark.png` |
| G4 Scheduled empty | `scheduled-empty-*.png` | `actual/scheduled-empty-dark.png` |
| G5 Customize skills | `customize-skills-*.png` | `actual/customize-skills-dark.png` |
| G6 Projects / Artifacts | `cowork-projects-*.png`, `cowork-artifacts-*.png` | `actual/cowork-projects-dark.png`, `actual/cowork-artifacts-dark.png` |
| G7 Settings Code | `settings-code-*.png` | `actual/settings-code-dark.png` |
| G8 Settings General (Dark) | `settings-general-*.png` | `actual/settings-general-dark.png` |

Light-theme actual PNGs were not captured (theme toggle lives in Settings → General; no separate in-shell shortcut yet).

## G1 Code home — region check (actual vs golden)

**Present in both:** cowork mascot + personalized heading, usage card with Overview/Models and All/30d/7d, six-metric grid + heatmap row, Local + folder row, code-input mascot, composer placeholder, + / Manual / model / speed **—** / High effort, sidebar traffic lights + collapse + search + mode switch + nav + Tasks heading.

**Mismatches (structural / copy / metrics):**

- **Metric values:** golden shows sample session totals; actual reads live store zeros and **—** placeholders (correct for empty DB, different from golden PNG).
- **Gatsby note:** hidden at zero tokens per product spec; golden still shows the sample sentence.
- **Heatmap:** actual renders an empty 26-cell grid; golden has level-1/2 cells on three days.
- **Model button:** shows loaded identifier `scripted`; golden uses a longer vendor-style name (substituted in product; not forbidden in app).
- **Typography & spacing:** SwiftUI layout approximates handoff CSS but is not pixel-identical to HTML (font metrics, composer corner radius, mascot offset).
- **Sidebar:** Tasks list body is empty until a task has messages or the thread is open; golden prototype may show sample rows when seeded.

## G4 Scheduled empty — region check

**Present in both:** title band, intro with `/schedule`, awake sentence + **Keep awake**, empty **No scheduled tasks yet.**, six example cards with titles/descriptions/times, toolbar search control, **Sort by** / **Next run** (or **Name**) popover, **New task** menu (**Create scheduled task**, **New task**).

**Still open vs golden:**

- **Illustration:** golden stopwatch SVG; actual uses SF Symbol stopwatch.
- **Wave divider:** not drawn between empty state and examples.
- **Layout density:** example grid spacing and page width differ slightly from HTML at 1440.

## G3 / G7 / G8 — navigation

- **Task thread:** sidebar **Task** row after activity or when the thread is active; `YUZU_UI_ROUTE=coworkTask` for capture.
- **Settings:** account **Yuzu Beta** menu → **Settings** (⌘,), or `YUZU_UI_ROUTE=settingsCode` / `settingsGeneral`; Code and General tabs use `settings-tab-Code` / `settings-tab-General`.

## Other routes (brief)

- **G2:** Both show Cowork home greeting + ideas + empty composer; layout density and typography differ (HTML vs SwiftUI). Cowork heading still lacks mascot + time-of-day name line from handoff.
- **G5:** Golden **Yuzu** skills banner and skill list styling; actual **Add your first skills** card — same region, different visual/copy.
- **G6:** Empty panels match in spirit (no project / no artifacts + CTA); golden uses panel layout from HTML shell, actual uses centered serif empty state.

## Verdict

**G1, G3, G4, G7, and G8** cover the required regions in dark theme with in-app navigation or launch routes. **Pixel-perfect sign-off is still not met** — SwiftUI vs HTML typography/spacing, light-theme actuals, scheduled empty-state illustration/divider, and golden sample metrics/heatmap. Harness accessibility tests (V1–V8) remain green.

## Still open (summary)

- Light-theme `actual/*-light.png` captures.
- Pixel spacing and font metrics vs handoff HTML across all routes.
- Scheduled empty-state stopwatch asset and wave divider.
- Cowork home mascot + time-of-day greeting line (G2).
- Customize skills visual parity with golden banner/list (G5).
