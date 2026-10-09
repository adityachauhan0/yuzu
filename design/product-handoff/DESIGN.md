# Code · Cowork design system

This guide is for extending the existing editable prototype in `index.html`. It records the interface that is already there, including the dark and light color schemes, and gives a consistent recipe for the next screen. The HTML and its CSS variables are the implementation source of truth. When a documented value and source code disagree, inspect the current source before changing either.

## Product character and scope

The product is a quiet, desktop-first workbench. Code and Cowork share one window shell, sidebar, navigation language, settings modal, and brand mascot. The visual character is compact and deliberate: graphite or cool-gray foundations, restrained pastel sage, fine outlines, clear text, and almost no decorative color. New screens should feel like a continuation of that shell, rather than a separate app.

Preserve the existing information architecture: Code and Cowork are modes within the same shell; Cowork contains Home, Greeting chat, Scheduled tasks, and Customize; the account menu opens Settings. Reuse existing controls and page regions where possible. Do not introduce a new top-level navigation system for an ordinary new page.

## Color system

The root of `index.html` defines dark colors in `:root` and light colors in `:root[data-theme="light"]`. Prefer semantic variables when writing new UI. Do not use a dark literal and expect automatic light-theme conversion.

| Role | CSS variable | Dark | Light | Use |
| --- | --- | --- | --- | --- |
| Main canvas | `--canvas` | `#1B1D20` | `#F3F5F2` | Main content and modal body |
| Sidebar | `--side` | `#16181B` | `#E8ECE8` | Shared navigation surfaces |
| Raised surface | `--surface` | `#24272A` | `#FFFFFF` | Composer and prominent cards |
| Hover surface | `--surface-hover` | `#2D3135` | `#E1E8E2` | Hover and subdued controls |
| Selected surface | `--selected` | `#373D40` | `#D9E3DB` | Current navigation and selected controls |
| Border | `--line` | `#3A4043` | `#CBD4CE` | Input and card edges |
| Quiet border | `--line-soft` | `#30373A` | `#D4DFD6` | Separators and shell boundaries |
| Primary text | `--text` | `#F0F2F1` | `#1C2923` | Main copy and titles |
| Secondary text | `--muted` | `#B9BFC0` | `#4F6157` | Descriptions and controls |
| Tertiary text | `--dim` | `#9DA5A6` | `#5B6D62` | Metadata and low-priority labels |
| Brand accent | `--accent` | `#B9D3C4` | `#567B64` | Brand presence and active emphasis |
| Focus | `--focus` | `#C8DFD1` | `#2E684C` | Visible keyboard focus ring |

The light scheme deliberately uses a **deeper sage for foreground accents**. The dark scheme uses pale sage against charcoal. Keep warm beige, peach, vivid green, and large gradient washes out of new page backgrounds. The bright traffic-light colors belong only to the window controls. The Settings code-theme preview contains fixed syntax-example colors; it is an example of code appearance, not a source for application colors. Existing `--tone-*` variables map older literal colors between themes; they are compatibility tokens, not a naming pattern to expand. Add or reuse a semantic role for a new repeated color.

For a new component, define all of its colors for both themes. Use text and an icon or shape for state, never color alone. Aim for at least 4.5:1 contrast for body text and 3:1 for large text and essential iconography in each theme. This is a requirement for future extensions; the current prototype has some compact labels and is not a certified accessibility implementation.

## Typography

No web fonts or font binaries are used. The page relies on installed platform faces, so line breaks can vary slightly across operating systems.

| Role | Stack | Current pattern |
| --- | --- | --- |
| Product UI | `-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif` | 16px root; common body and control text around 15–17px |
| Editorial display and assistant reply | `Georgia, "Times New Roman", serif` | Home welcome 40–51px, page heading 32–46px, assistant reply 20px |
| Technical snippets | `ui-monospace, SFMono-Regular, monospace` | Inline code and technical values; code-preview sample has its own extended fallback stack |

Use the serif sparingly for the welcome line, major Cowork headings, and the assistant's prose. Use the system sans stack for navigation, settings, controls, tables, and the Code dashboard. The Code greeting is a 25px sans heading. Keep controls readable; use 16px for new body copy with roughly 1.5 line height. Small 11–14px labels exist in the captured prototype for metadata, but they should not carry a new page's essential instruction or primary action. Do not replace the mascot or font pairing with stock decorative typography.

## Geometry and layout

The desktop app is one grid with a `256px` sidebar (`--sidebar-width`) and a flexible main pane. The primary Cowork composer and Code content column share an `806px` maximum (`--content-width`). The main column stays centered in the pane, with 32px desktop side room where possible. The app uses a subtle 13px outer radius; the composer uses `--radius: 22px`; ordinary rows and small controls tend to use 6–10px radii. Do not round every surface equally.

Build spacing with an 4px/8px rhythm. Typical row and control gaps are 8–16px; section separation is about 24–48px. Larger top whitespace on the home screens is intentional and should not be copied into dense settings or list pages. Keep primary regions in normal grid or flex flow. When the chat inspector opens on a wide desktop, it takes space beside the chat and the chat column re-centers in what remains. At narrower widths it becomes a right-side overlay. New inspector-like panels should follow the same behavior and retain an explicit close control.

Responsive behavior already exists in `index.html`:

- At `1240px` and below, the chat inspector overlays the conversation instead of squeezing it further.
- At `1024px` and below, the sidebar width reduces to `232px`.
- At `768px` and below, the sidebar becomes a toggleable drawer; content columns use 24px side gutters. The Code column follows the same width rule.
- At `480px` and below, the outer desktop window frame falls away, main gutters reduce to 16px, and compact controls wrap where needed.
- Settings changes from a two-column dialog to a stacked, full-width layout at `620px` and below.

For a new page, preserve these transitions and give content a sensible reading order at 375px. Do not scale the whole desktop UI down, hide essential actions, or create horizontal page scrolling. Allow long user content to wrap, truncate list data with a route to full detail, or move secondary details behind disclosure. Never crop authored headings merely to fit a card.

## Shared component language

| Pattern | Existing source pattern | How to extend it |
| --- | --- | --- |
| Window and navigation | `.app`, `.sidebar`, `.mode-switch`, `.nav-button` | Keep mode switching in the sidebar; mark the current route visibly and with `aria-current` or equivalent. |
| Cowork composer | `.composer-wrap`, `.composer`, `.composer-tools`, `.send` | Place the input above its tools; show a distinct ready state when text is present. |
| Code composer | `.code-footer`, `.code-form`, `.code-pixel`, `.code-bottom` | Keep it aligned to the same 806px column; retain the mascot's anchored placement and the compact model/speed group. |
| List or task row | `.task-list button`, `.skill-row`, `.created-item` | Use a clear leading label, restrained metadata, and a whole-row target when the row navigates. |
| Tabs and segments | `.customize-tab`, `.code-tabs`, `.settings-segment` | Use selected background plus text contrast; expose selected state in ARIA. |
| Menus | `.popover`, `#account-menu` | Anchor near the trigger, use 6–7px inner row radii and dividers sparingly, close on selection or dismissal. |
| Modal settings | `.settings-backdrop`, `.settings-dialog`, `.settings-sidebar`, `.settings-row` | Keep persistent labels above or beside controls; use short helper copy; provide a visible close path. |
| Chat and details | `.thread-view`, `.thread-content`, `.thread-inspector` | Reserve layout space on wide screens; overlay only when constrained. Keep expand/collapse controls labeled. |

Use the existing outline icon family: `.icon` is 18×18px with a `1.65` stroke and rounded caps/joins; `.small` is 16×16px and `.tiny` is 14×14px. Keep icons from the inline SVG symbol set in `index.html` at the same hierarchy. Do not substitute emoji, mixed filled/outlined icon styles, or a large icon beside every heading.

For a new form, provide a persistent visible label and actionable error text. For empty states, say what is missing and offer the next useful action. Show feedback after local actions. Primary actions may use the light text-color fill in dark mode and the corresponding dark fill in light mode; avoid placing several equal-strength filled buttons in one view.

## Interaction and accessibility

The page starts in Dark. Settings → General → Appearance offers Light, Dark, and System. `applyTheme()` sets `data-theme` on the root, updates the browser theme color, and swaps each `img[data-mascot]` source. System follows the operating system preference while that option is selected. Theme choice is local to the open page and resets to Dark on reload; do not describe it as a saved account preference.

Preserve keyboard-reachable semantic buttons and inputs, visible `:focus-visible` outlines using `--focus`, proper labels, and state attributes (`aria-expanded`, `aria-pressed`, `aria-selected`, `aria-current`) when adding controls. Menus, panels, and dialogs need an exit and return path. The current hover changes run at about 180ms with `--ease: cubic-bezier(.2,.8,.2,1)`. Honor `prefers-reduced-motion`; the existing style reduces transition and animation durations to nearly zero. Motion should explain a state change only.

The present prototype demonstrates local interactions. Chat replies, scheduled jobs, account actions, file trust, MCP configuration, and Code usage are not connected to the original services. The visible usage figures and `320 tok/s` are sample content, not live metrics. New UI should label unconnected values or actions honestly and should not invent product performance claims.

## Mascots and assets

The cat mascot is owner-supplied artwork. Its silhouette and facial details are locked; the dark and light SVGs differ only in theme fitting. The pixel-style Code input mascot is likewise supplied and should keep its geometry. Use these local files, never a remote hotlink or a re-drawn approximation:

| Context | Dark file | Light file |
| --- | --- | --- |
| Cowork account row, welcome, replies, Code heading | `assets/cowork-logo.svg` | `assets/cowork-logo-light.svg` |
| Code composer mascot | `assets/code-input-mascot.svg` | `assets/code-input-mascot-light.svg` |

The cat SVG has intrinsic dimensions `850×780`; the Code mascot has `1448×1086`. Keep both files' full frames and intrinsic aspect ratios. The existing account mark is 28px wide; the welcome mark is 42px wide on desktop; the Code mascot is 56px wide and anchored 16px from the right of the input bar. The JS asset switch relies on `data-mascot="cowork"` or `data-mascot="code"`. When adding another appearance of either mascot, use that attribute so Light, Dark, and System all update it. Decorative instances use empty alt text; give a genuinely informative instance an accessible name through its enclosing control or meaningful alt text.

## Recipe for the next UI

1. Start inside the existing `.app` and reuse its sidebar, main pane, and modal layer. Choose the existing Code or Cowork mode rather than creating a second shell.
2. Put the main content in the existing width system. Use the 806px column for composer-led or dashboard content; use a wider list layout only when the existing Scheduled or Customize pattern supports it.
3. Style every new surface and state in both `:root` themes with semantic color roles. Keep pastel sage as a controlled accent, with the deeper light-theme variant for readable foreground use.
4. Reuse the system sans/Georgia/monospace roles, outline icons, restrained radii, and existing control states. Use the correct local mascot variant through `data-mascot`.
5. Implement actual navigation and local feedback for every visible control. Mark prototype-only behavior as such instead of implying a connected service.
6. Check the new design concept at desktop, tablet, and 375px mobile sizes; consider both color schemes, keyboard focus, reduced motion, and variable-length text before handing it to engineering.

The handoff bundle's `README.md` explains how to open the prototype and which interactions are local. This document specifies how to extend its design; it is not a claim that the existing prototype is production-ready or has completed an accessibility audit.
