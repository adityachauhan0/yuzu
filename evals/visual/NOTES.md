# Visual verification — `cursor/harness-architecture`

Captured **2026-10-10** on macOS (arm64). Goldens from `design/product-handoff/index.html` at 1440×900 via headless Chrome + in-page route setup. Actuals from Debug `Yuzu.app` window captures (`screencapture -l <windowid>`), driven with Accessibility + CGEvent clicks where identifiers were clickable.

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

**Present in both:** sidebar, Code mode switch (Code selected), usage-style metrics row, Local + folder affordance, composer, Manual control, speed/effort area at bottom of composer.

**Mismatches (not pixel-perfect; structural/copy):**

- **Page heading:** golden uses mascot + “What’s up next, …”; actual uses plain **Code** title with Overview/Models sub-nav only.
- **Metrics chrome:** golden wraps metrics in a usage card with **All / 30d / 7d**; actual shows three zero metrics inline with **—** speed label (no period toggles, no heatmap — aligned with harness intent, unlike raw handoff HTML).
- **Composer chrome:** golden shows code-input mascot, full **model** button, explicit **—** speed, and **High** effort; actual composer is simpler (**+**, **Manual**, **High**, send) with no model name row.
- **Sidebar chrome:** golden includes collapse, search, pinned/tasks; actual sidebar is slimmer (decorative traffic lights, no search/tasks list).
- **Copy:** golden still contains prototype strings (e.g. personalized heading); actual uses neutral **Code** / zeros — closer to `VisualEvalTests` expectations.

## Other routes (brief)

- **G2:** Both show Cowork home greeting + ideas + empty composer; layout density and typography differ (HTML vs SwiftUI).
- **G4:** Golden shows intro, keep-awake notice, and **six schedule examples**; actual is a minimal empty line (“No scheduled tasks yet.”) only.
- **G5:** Golden **Yuzu** skills banner and skill list styling; actual **Add your first skills** card — same region, different visual/copy.
- **G6:** Empty panels match in spirit (no project / no artifacts + CTA); golden uses panel layout from HTML shell, actual uses centered serif empty state.

## Verdict

**G1 does not visually match the golden PNG** (same coarse regions, different heading, sidebar chrome, composer/model row, and metrics presentation). **G4/G5/G6 are partial** against goldens (missing examples, copy/styling gaps). **G3, G7, G8** need settings/task automation or UI hooks before window capture. Harness accessibility tests can be green while these window diffs remain; this pass is **not** a visual sign-off.
