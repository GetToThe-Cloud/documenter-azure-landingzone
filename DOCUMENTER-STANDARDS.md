# Azure Documenter Standards

This document is the shared contract for the standalone Azure documenters and future documenters built from the same pattern. It is intentionally stricter about interfaces and security than about product-specific inventory details.

## Product profiles

| Profile | Collector and server | Assessment configuration | Product-specific focus |
| --- | --- | --- | --- |
| Azure Virtual Desktop | `Get-AVDInventoryData`, `Start-AVDInventoryServer.ps1` | `waf-config.json` | Host pools, session hosts, workspaces, application groups, scaling plans, galleries, and networks |
| Azure Local | `Get-AzureLocalInventory`, `Start-AzureLocalServer.ps1` | `waf-config.json` | Clusters, nodes, VMs, logical networks, Arc services, storage, and Hybrid Benefit cost analysis |
| Azure Landing Zone | `Get-AzureLandingZoneInventory`, `Start-AzureLandingZoneServer.ps1` | `scoring-config.json` plus `waf-config.json` | Management groups, subscriptions, policy, RBAC, networking, and governance |
| New documenter | `Get-<Domain>Inventory`, `Start-<Domain>Server.ps1` or a unified server route | Choose the assessment model deliberately | Define the domain inventory and permissions before implementation |

Default ports, required Az modules, authentication behavior, and distribution channels are product decisions. Do not normalize them just because the file layout is shared.

## Shared file roles

Standalone documenters normally contain:

- A `.psd1` manifest with module metadata, version, required modules, exports, and package files.
- A `.psm1` module that exposes the public collector and server functions.
- A `Get-*Inventory.ps1` collector that returns structured PowerShell data.
- A `Start-*Server.ps1` HTTP listener that serves static files and JSON API endpoints.
- `index.html`, `app.js`, and `styles.css` for the browser dashboard.
- WAF, CAF, or scoring JSON plus a guide when the assessment is configurable.
- `README.md` and `CHANGES.md` or `changes.md`.

The unified documenter may use `server.js`, `package.json`, `public/`, `scripts/`, and persisted cache directories instead. Its async collection and Express routes are valid product-specific architecture, not a reason to reshape the standalone projects.

## Runtime contracts

### Collector to server

The collector must return a serializable object with stable top-level sections. Names differ by product, but the server and browser must agree on them. Use explicit defaults for empty sections so a missing Azure resource does not become a browser exception.

When the collector is invoked:

- Keep it read-only and honor the current authentication and subscription scope.
- Preserve cross-subscription behavior already supported by the product.
- Keep progress output separate from the JSON data channel.
- Use `ConvertTo-Json -Depth 20` or a deliberate equivalent when nested data requires it.
- Do not add a new Az module without updating the manifest and the product's prerequisite/module installation path.

### Server to browser

Existing dashboards commonly use these routes:

| Route | Purpose | Compatibility rule |
| --- | --- | --- |
| `/api/auth/status` | Report Azure authentication state and context | Keep the response safe to display; do not return tokens |
| `/api/auth/login` | Start device or interactive login | Use the existing POST and CSRF behavior |
| `/api/inventory/data` | Return inventory or start/poll collection | Preserve the current synchronous or asynchronous contract |
| `/api/progress` | Report long-running collection progress | Keep percentage/status/completed semantics if present |
| `/api/waf/config` or the product equivalent | Serve assessment configuration | Keep the server-loaded source of truth |

If a route or response shape changes, change its caller in `app.js` in the same work item and document the compatibility impact.

### Assessment configuration

Configuration files differ by product, but the safe baseline is:

- A semver `version` string.
- A `pillars`, `categories`, or equivalent object.
- Unique rule IDs within the configuration.
- Numeric points or scores.
- Explicit condition operators limited to `===`, `==`, `!==`, `!=`, `>=`, `<=`, `>`, and `<` where the current evaluator supports them.
- Human-readable success, failure, and recommendation text.

Do not use executable expressions in JSON. Keep condition parsing in a strict, testable function. If a configuration schema changes, update its guide and add a validation example.

## Security requirements

### Browser rendering

- Treat every Azure name, ID, tag, description, message, and status as untrusted.
- Use the existing `escapeHtml` helper before interpolating a value into HTML, or use `textContent`.
- Do not place untrusted values in an inline `onclick` or another executable attribute.
- Keep PDF/export code on the escaped or DOM-rendered representation.

### Server and authentication

- Bind local servers to the intended local interface and preserve Host/Origin checks already present.
- Reject cross-origin state-changing requests according to the product's existing CSRF convention.
- Return generic error messages to the browser and keep diagnostic details in server logs.
- Store Azure context only in the existing per-user protected location and remove temporary copies during cleanup.
- Install missing modules only with explicit user consent. Do not silently update modules at startup.

### Dependencies and repository hygiene

- Keep SRI hashes for CDN resources and review hash changes as security-sensitive changes.
- Do not commit `.env` files, credentials, context JSON, generated inventory, cache content, or export files.
- Treat changes to authentication, permissions, module installation, CORS, CSP, SRI, or HTML rendering as security changes in the changelog.

## Documentation and versioning

Use the naming and casing already present in the product. Existing projects use both `CHANGES.md` and `changes.md`; do not create a duplicate file only to standardize casing.

For a user-facing change:

1. Update the authoritative version source using an existing version helper when one exists.
2. Add a dated changelog entry under the existing Added, Changed, Fixed, or Security heading.
3. Update README setup, feature, configuration, or troubleshooting text as needed.
4. Update `WAF-CONFIG-GUIDE.md` or the relevant configuration documentation when JSON rules or fields change.
5. Verify manifest `FileList`, exports, package scripts, and visible version labels remain coherent.

Documentation-only maintenance may not require a product version bump when the repository's existing policy says so. When in doubt, inspect the current changelog and manifest/package conventions before deciding.

## New documenter checklist

- [ ] Choose a product name, public PowerShell function names, default port, authentication scope, and distribution channel.
- [ ] Record the profile in `documenter-profile.json` or an equivalent design note.
- [ ] Define the inventory top-level sections and empty/default values.
- [ ] Implement the collector with read-only permissions and PowerShell 7 support.
- [ ] Implement the server route contract and a safe error path.
- [ ] Build the vanilla JavaScript dashboard with escaping and no executable data expressions.
- [ ] Add the assessment configuration, strict evaluator, and a configuration guide.
- [ ] Add the manifest/module exports and ensure every shipped file is packaged.
- [ ] Add README prerequisites, permissions, startup, troubleshooting, and export behavior.
- [ ] Add a changelog entry, version source, and focused validation commands.
- [ ] Install this standards pack and run the onboarding, security, and documentation agents before the first release.

## Validation checklist

Run the narrow checks relevant to the change:

```powershell
# JavaScript syntax
node --check .\app.js

# PowerShell syntax with PowerShell 7
$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path .\Get-<Domain>Inventory.ps1),
    [ref]$tokens,
    [ref]$parseErrors
) | Out-Null
$parseErrors

# JSON syntax
Get-Content .\waf-config.json -Raw | ConvertFrom-Json | Out-Null

# Whitespace errors
git diff --check
```

A live Azure inventory, browser interaction, PSGallery publish, container build, or deployment is a separate check and must be named explicitly in the final report if it was run.
