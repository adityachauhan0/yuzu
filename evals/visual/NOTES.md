# Visual verification — `cursor/harness-architecture`

Captured **2026-10-10** on macOS (arm64). Goldens from `design/product-handoff/index.html` at 1440×900 via headless Chrome + in-page route setup. Actuals from Debug `Yuzu.app` window captures (`screencapture -l <windowid>`), driven with coordinate click for Scheduled nav where AXPress on identifiers was unreliable.

## Routes captured

| Route | Golden (dark/light) | Actual (dark) |
| --- | --- | --- |
| G1 Code home | `code-home-*.png` | `actual/code-home-dark.png` |
| G2 Cowork new | `cowork-new-*.png` | `actual/cowork-new-dark.png` |
| G3 Task + inspector | `cowork-task-*.png` | **open** — no task entry in sidebar; could not open thread without sending a message (composer typing not automated reliably) |
| G4 Scheduled empty | `scheduled-empty-*.png` | `actual/scheduled-empty-dark.png` |
| G5 Customize skills | `customize-skills-*.png` | `actual/customize-skills-dark.png` |
| G6 Projects / Artifacts | `cowork-projects-*.png`, `cowork-artifacts-*.png` | `actual/cowork-projects-dark.png`, `actual/cowork-artifacts-dark.png` |
| G7 Settings Code | `settings-code-*.png` | **open** — `Yuzu Beta` footer control did not present `settings-dialog` to automation |
| G8 Settings General (Dark) | `settings-general-*.png` | **open** (same blocker as G7) |

Light-theme actual PNGs were not captured (no in-app theme toggle reachable without settings).

## G1 Code home — region check (actual vs golden)

**Present in both:** cowork mascot + personalized heading, usage card with Overview/Models and All/30d/7d, six-metric grid + heatmap row, Local + folder row, code-input mascot, composer placeholder, + / Manual / model / speed **—** / High effort, sidebar traffic lights + collapse + search + mode switch + nav + Tasks heading.

**Mismatches (structural / copy / metrics):**

- **Metric values:** golden shows sample session totals (6 sessions, 574 messages, 50.3M tokens, peak hour, favorite model label); actual reads live store zeros and **—** placeholders (correct for empty DB, different from golden PNG).
- **Gatsby note:** hidden at zero tokens per product spec; golden still shows the sample sentence.
- **Heatmap:** actual renders an empty 26-cell grid; golden has level-1/2 cells on three days.
- **Model button:** shows loaded identifier `scripted`; golden uses a longer vendor-style name (substituted in product; not forbidden in app).
- **Typography & spacing:** SwiftUI layout approximates handoff CSS (card width, footer stack) but is not pixel-identical to HTML (font metrics, composer corner radius, mascot offset).
- **Sidebar:** Tasks list body is empty (no sessions); golden prototype may show sample rows when seeded.

## G4 Scheduled empty — region check

**Present in both:** title band, intro with `/schedule`, awake sentence + **Keep awake**, empty **No scheduled tasks yet.**, six example cards with titles/descriptions/times.

**Mismatches:**

- **Chrome:** golden toolbar uses icon search, sort popover, and **New task** menu; actual uses simplified static controls (no popovers).
- **Illustration:** golden stopwatch SVG; actual uses SF Symbol stopwatch.
- **Wave divider:** not drawn between empty state and examples.
- **Layout density:** example grid spacing and page width differ slightly from HTML at 1440.

## Other routes (brief)

- **G2:** Both show Cowork home greeting + ideas + empty composer; layout density and typography differ (HTML vs SwiftUI). Cowork heading still lacks mascot + time-of-day name line from handoff.
- **G5:** Golden **Yuzu** skills banner and skill list styling; actual **Add your first skills** card — same region, different visual/copy.
- **G6:** Empty panels match in spirit (no project / no artifacts + CTA); golden uses panel layout from HTML shell, actual uses centered serif empty state.

## Verdict

**G1 and G4 are much closer** on required regions (heading, usage chrome, composer footer, scheduled intro/awake/examples). **Pixel-perfect sign-off is still not met** — metric sample data, heatmap fill, Gatsby note visibility, HTML-only toolbar popovers, and SwiftUI vs HTML typography. **G3, G7, G8** need settings/task automation or UI hooks before window capture. Harness accessibility tests (V1–V8) are green; this pass updates actual PNGs for G1/G4 only.
