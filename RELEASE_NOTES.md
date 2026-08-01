# ClaudePulse 0.2.0

Plan detection now works, and per-model limits are surfaced.

## Fixed

- **The plan always showed "unknown."** Claude's usage endpoint returns rate-limit windows only — it carries no plan, tier, or subscription field, so the parser had nothing to match. ClaudePulse now makes a second, hourly-cached request to the organizations endpoint and resolves the plan from there, normalising raw tiers into display names such as `Max 5x`, `Max 20x`, `Pro`, and `Team`. A failed plan lookup never fails a usage refresh, and the menu hides the row rather than showing "unknown".
- Credit pools in the usage payload (`spend`, `extra_usage`) expose a percentage but never reset, and were at risk of being rendered as fake rate-limit windows. Only resetting windows count as limits.
- A top-level `limits` key could have been mistaken for a usage container, dropping both real windows. The parser now only descends into a container that actually yields windows.

## Added

- **Per-model limits in the menu and Diagnostics.** These were parsed and cached but never displayed. Buckets are discovered generically rather than from a fixed list, so a model shipping its own separate weekly limit — Fable, for instance — appears with no code change.
- **Reset time preference** with three formats: `resets 13:27`, `resets in 4h 42m`, or `resets 13:27 (in 4h 42m)`. Applies to the window rows, per-model rows, and Diagnostics. A window whose reset has already passed reads "now" rather than counting up from zero.

## Changed

- The two near-identical display formatters are now one. Localisation is injected as data, so the code path the app ships is the code path the tests cover.
- Settings decode field by field with per-field defaults, so preferences saved by an older build survive a new field instead of silently resetting.

## Privacy

ClaudePulse makes authenticated read requests to Claude's own endpoints using Claude Desktop's local cookies. It does not send telemetry, contact third-party services, or display cookie values.

This build is ad-hoc signed, so macOS may ask for confirmation the first time you open it. If that happens, right-click `ClaudePulse.app`, choose **Open**, then confirm.
