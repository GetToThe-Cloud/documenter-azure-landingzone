<!-- DOCUMENTER-STANDARDS:START -->
# Azure Documenter Engineering Instructions

These instructions are the shared baseline for every Azure documenter project. Read `DOCUMENTER-STANDARDS.md` before changing a collector, server, dashboard, assessment configuration, or release file.

## Working method

- Identify the documenter profile before editing: Azure Virtual Desktop, Azure Local, Azure Landing Zone, or a new product.
- Preserve the product-specific inventory model, Azure module set, assessment type, default port, and distribution method. Similar structure does not mean identical behavior.
- Before the first edit, inspect the owning code path and state one falsifiable hypothesis plus one focused check.
- Make the smallest change that tests the hypothesis. After the first edit, run the narrowest available validation before broadening the work.
- Use the `documenter-coordinator` agent for cross-layer work. It can hand off to `documenter-inventory`, `documenter-web`, `documenter-security`, `documenter-docs-release`, and `documenter-onboarding`.

## Shared architecture

- PowerShell 7+ collectors gather read-only Azure inventory.
- A PowerShell `HttpListener` server is used by the standalone documenters. A Node.js/Express server is allowed for the unified documenter.
- `index.html`, `app.js`, and `styles.css` provide the portable vanilla JavaScript dashboard.
- WAF, CAF, or compliance JSON is loaded by the server and exposed through an API; do not silently embed a second copy in `app.js`.
- Keep the collector-to-server JSON shape and the server-to-browser endpoints stable. If a contract must change, update both sides, documentation, and the version entry together.

## Security baseline

- Escape Azure-sourced values before assigning them to `innerHTML`; prefer `textContent` for plain text.
- Do not add `eval`, `Function`, `Invoke-Expression`, or string-built PowerShell execution.
- Do not build inline event handlers from data. Use `data-*` attributes and delegated listeners when interaction needs a dynamic value.
- Do not restore wildcard CORS. Keep local servers same-origin and validate localhost Host/Origin values where the existing server does so.
- State-changing endpoints must use POST and the existing CSRF convention.
- Keep SRI and `crossorigin` attributes on CDN assets when the project uses CDN scripts or styles.
- Never commit tokens, Azure context files, inventory output, cache data, or local authentication files.

## Documentation and release hygiene

- Update the existing README, WAF/configuration guide, and `CHANGES.md` or `changes.md` when behavior, setup, configuration, security, or UX changes.
- Keep the authoritative version source consistent: the module manifest for standalone projects and `package.json` for the unified project. Update visible version strings only when their source is not generated.
- Use semantic versioning. Do not publish, tag, push, or deploy unless explicitly requested.
- Never claim that live Azure collection, browser verification, packaging, or deployment was tested unless it was actually run.

## Focused validation

- JavaScript: `node --check` for every changed JavaScript file.
- PowerShell: parse every changed script with PowerShell 7 and run focused non-Azure checks that are available.
- JSON: load changed configuration with `ConvertFrom-Json` and validate required fields and unique rule IDs.
- Repository: run `git diff --check` and inspect the complete diff before release work.

See `DOCUMENTER-STANDARDS.md` for the contracts, product profiles, onboarding checklist, and release checklist.
<!-- DOCUMENTER-STANDARDS:END -->
