# Changes

## v1.3.0 — Detailed networking inventory and export

- Added flat subnet inventory with address prefixes, delegations, service endpoints, route-table references, and NSG references.
- Added route-table inventory with user-defined routes, next-hop details, BGP propagation, and associated subnet links.
- Added direct Virtual Hub inventory with Virtual WAN references, routing state, and connected VNet links.
- Fixed Virtual Hub discovery by resolving each hub with its resource group instead of relying on an unsupported tenant-wide `Get-AzVirtualHub` call.
- Added complete custom and default NSG rule records plus explicit subnet and NIC association records.
- Added dashboard and branded PDF tables for subnets, UDRs, Virtual Hubs, NSG rules, and NSG associations.

## v1.2.0 — Report styling and server shutdown (2026-08-12)

- Added reliable asynchronous Ctrl+C shutdown for the PowerShell HttpListener.
- Added the packaged GetToTheCloud wordmark and a binary logo route for PDF generation.
- Recreated the AVD PDF styling with a branded cover, navy/azure palette, section dividers, interior headers, and responsive page footers.
- Kept the existing Landing Zone CAF, WAF, inventory, and recommendation content unchanged.

## v1.1.0 — Security hardening release

Full remediation of the findings from the security audit of this repository.
Files changed: `Start-AzureLandingZoneServer.ps1`, `Get-AzureLandingZoneInventory.ps1`,
`app.js`, `index.html`, `README.md`, `documenter-azure-landingzone.psd1`.

---

### High severity — fixed

#### H1. Wildcard CORS header removed
- **Issue:** Every API response included `Access-Control-Allow-Origin: *`, allowing any website open in the browser to read the full inventory (subscriptions, policies, role assignments, network topology) from the local API.
- **Fix:** The header is no longer sent, so the browser's same-origin policy applies. Responses now also include `X-Content-Type-Options: nosniff`.
- **Where:** `Start-AzureLandingZoneServer.ps1` (response header block).

#### H2. CSRF protection for state-changing endpoints
- **Issue:** `/api/auth/login` and `/api/inventory/refresh` accepted simple GET requests, so any web page could trigger an Azure device-code login or a full tenant inventory collection just by embedding a link/image.
- **Fix:** Both endpoints now require a **POST** request carrying the header `X-Requested-With: XMLHttpRequest` (which cross-origin pages cannot attach without a CORS preflight). Non-conforming requests get **403 Forbidden**. The frontend sends the header via a shared `CSRF_HEADERS` constant.
- **Where:** `Start-AzureLandingZoneServer.ps1` (request guard + `__forbidden__` route), `app.js` (`requestAzureLogin`, `refreshInventory`).

#### H3. Azure token context written to predictable world-readable temp path
- **Issue:** `Save-AzContext` wrote the serialized Azure context — including access/refresh token material — to a fixed, predictable file in the shared system temp directory, readable by other local users, and it could linger after crashes.
- **Fix:** Context and progress files now live in a per-user app directory `~/.documenter-azure-landingzone/` created with `chmod 700` (non-Windows); the context file gets `chmod 600` via the new `Save-ServerAzContext` helper. The file is deleted **immediately** after the collector runspace imports it, and again in the server's `finally` block on shutdown.
- **Where:** `Start-AzureLandingZoneServer.ps1` (`$script:AppDataDir`, `Save-ServerAzContext`, runspace import, `finally`), `Get-AzureLandingZoneInventory.ps1` (same directory derivation for the progress file).

#### H4. Arbitrary code execution via `Invoke-Expression` / `eval()` on config conditions
- **Issue:** Scoring and WAF rule conditions from `scoring-config.json` / `waf-config.json` were evaluated with PowerShell `Invoke-Expression` and JavaScript `eval()`. A tampered or malicious config file could execute arbitrary code in the collector or the browser.
- **Fix:** Both evaluators were replaced with strict, grammar-restricted parsers that only accept `token op token` comparisons (`>= <= == != > <`), bare boolean metrics, and `AND`/`OR` combinations (AND binds tighter):
  - PowerShell: `Resolve-ConditionToken`, `Test-ConditionComparison`, `Test-ScoringCondition`.
  - JavaScript: `resolveConditionToken`, `evaluateComparison`, rewritten `evaluateWAFCondition`.
  Unknown tokens or malformed expressions throw / evaluate to false instead of executing anything.
- **Where:** `Get-AzureLandingZoneInventory.ps1`, `app.js`.

#### H5. Stored XSS throughout the dashboard
- **Issue:** Azure-derived values (resource names, tags, policy descriptions, scopes, firewall rule fields, recommendations, etc.) were interpolated directly into `innerHTML` templates in ~50 places. A resource name like `<img src=x onerror=...>` anywhere in the tenant would execute script in the dashboard.
- **Fix:** Added an `escapeHtml()` helper (aliased `esc`) and applied it to **every** data interpolation rendered via `innerHTML`, across auth UI, management groups, subscriptions, policies, role assignments, all networking tables (VNets, peerings, VPN/vWAN, firewalls + full firewall-policy rule rendering, NSGs, private DNS, private endpoints), governance (budgets, locks, tags), best-practice recommendations, VM tables + VM details modal, resource detail panels, and the scoring/WAF configuration views.
- **Where:** `app.js`.

---

### Medium severity — fixed

#### M6. No Subresource Integrity or Content-Security-Policy on CDN assets
- **Issue:** vis-network, jsPDF and html2canvas were loaded from cdnjs with no integrity pinning; a compromised CDN response would run with full access to the inventory data.
- **Fix:** All four CDN tags now carry `integrity="sha384-..."` + `crossorigin="anonymous"`, and a CSP `<meta>` tag restricts script/style/font sources to `'self'` + cdnjs, blocks objects and framing, and limits `connect-src` to `'self'`. (`'unsafe-inline'` remains required by the dashboard's inline handlers; the primary XSS defense is H5's escaping.)
- **Where:** `index.html`.

#### M7. Forced automatic module install/update on startup
- **Issue:** Startup ran `Install-Module`/`Update-Module` with `-Force -AllowClobber`, silently replacing the user's installed Az module versions (supply-chain and stability risk).
- **Fix:** Renamed to `Install-RequiredModule`: modules are installed (PSGallery, `-Scope CurrentUser`) **only if missing**, without `-AllowClobber`. If an update is available, the server just prints a notice suggesting a manual `Update-Module <name>`.
- **Where:** `Start-AzureLandingZoneServer.ps1`; documented in `README.md`.

#### M8. Exception details leaked to API clients
- **Issue:** Raw exception messages (paths, module internals, Azure error payloads) were returned in JSON error responses.
- **Fix:** Clients now receive generic error messages; full exception details are written to the server console only.
- **Where:** `Start-AzureLandingZoneServer.ps1` (login, collection-start, progress-completion handlers).

#### M9. Progress file in shared temp directory
- **Issue:** `inventory-progress.json` was written to the world-readable shared temp directory with a predictable name (information disclosure / pre-creation tampering).
- **Fix:** Moved to the same protected per-user directory as H3 (`~/.documenter-azure-landingzone/inventory-progress.json`); both scripts derive the path identically.
- **Where:** `Start-AzureLandingZoneServer.ps1`, `Get-AzureLandingZoneInventory.ps1`.

---

### Low severity — documented (accepted risk)

#### L10. No authentication on the dashboard itself
- Any process/user on the same machine can browse `http://localhost:<port>` and read collected data or trigger actions (now limited by H2's CSRF guard). Mitigated by the 127.0.0.1 binding and `HttpListener` host validation. Documented in the README security section; run only on trusted single-user machines.

#### L11. Plain HTTP transport
- Traffic is unencrypted, but never leaves the loopback interface. Acceptable for a localhost-only tool; documented.

#### L12. Single-threaded request handling
- One slow request blocks the listener (local DoS only). No security impact beyond availability on the local machine; documented.

---

### Documentation
- `README.md`: rewrote the **Security** section (accurate token-handling, CSRF, same-origin, safe evaluator, SRI/CSP claims) and corrected the module-management section (install-if-missing, no auto-update).
- `documenter-azure-landingzone.psd1`: version bumped `1.0.0` → `1.1.0` with release notes referencing this file.
