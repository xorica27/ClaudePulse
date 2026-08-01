# ClaudePulse 0.1.0

Initial ClaudePulse build.

## What's Included

- macOS menu bar app that reads Claude usage locally.
- Claude usage client that reads Claude Desktop's encrypted local cookies and calls Claude's own usage endpoint.
- Local storage scanner fallback for Claude app support data, IndexedDB, Session Storage, Local Storage, and logs.
- Exact-data rule: ClaudePulse shows compact usage only when a structured usage payload is found.
- Clear unavailable, cached, and stale states instead of estimated usage.
- Preferences, diagnostics, launch-at-login support, and optional notifications.

## Privacy

ClaudePulse makes an authenticated read request to Claude's own usage endpoint using Claude Desktop's local cookies. It does not send telemetry, contact third-party services, or display cookie values.

This build is ad-hoc signed, so macOS may ask for confirmation the first time you open it. If that happens, right-click `ClaudePulse.app`, choose **Open**, then confirm.
