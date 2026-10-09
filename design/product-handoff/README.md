# Code · Cowork prototype — product handoff

Extract this ZIP intact and open `index.html` in a current desktop browser. It is the runnable entry and editable HTML/CSS/JavaScript source. No build tool, package manager, server, or network connection is needed.

## Contents

- `index.html` — the shared Code and Cowork shell, all prototype screens, both themes, inline interface icons, and local interactions.
- `DESIGN.md` — the design system for extending the UI: visual direction, both palettes, type, layout, components, responsive rules, accessibility, and mascot usage.
- `assets/cowork-logo.svg` and `assets/cowork-logo-light.svg` — the dark and light cat mascot variants.
- `assets/code-input-mascot.svg` and `assets/code-input-mascot-light.svg` — the dark and light Code input mascot variants.
- `SHA256SUMS` — checksums for the files above and this README.

The owner's reference images and unrelated project files are excluded. Asset paths stay relative to `index.html`. The supplied mascot shapes have not been redrawn; their theme colors differ.

## Themes and fonts

The prototype starts in Dark. Settings → General → Appearance offers Light, Dark, and System. System follows the current operating-system color preference. Selection is local to the open page and resets to Dark after reload. The Settings code-theme previews remain intentionally fixed samples. See `DESIGN.md` for the full color tables and future-screen guidance.

No font binaries are bundled. The source uses installed platform stacks: UI `-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif`; display `Georgia, "Times New Roman", serif`; technical text `ui-monospace, SFMono-Regular, monospace`. The root size is 16px. Browser and OS font availability can cause small glyph and line-break differences. Exact cross-platform typography would require a separately licensed and bundled font.

## Scope of the prototype

The entry includes the shared shell, Code home, Cowork home, Greeting chat with task details, Scheduled tasks, Customize/Skills, account menu, and Settings. Navigation and visible controls use local browser behavior. Usage figures and `320 tok/s` are static sample content. Chat generation, background schedules, account services, file trust, and MCP configuration are not connected to production services. Connect real services and data at the existing interaction points before shipping a product.

The mascot artwork was supplied by the project owner. This bundle does not add a separate licensing grant.
