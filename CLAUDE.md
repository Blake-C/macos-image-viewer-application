# Image Viewer — Claude Code Rules

## Project overview

A native macOS image gallery and viewer built with SwiftUI + AppKit on Swift Package Manager. No Xcode project file — the build entry point is `build-app.sh`. Minimum deployment target: macOS 14.

## Building

```bash
./build-app.sh          # produces ImageViewer.app at the project root
open ImageViewer.app    # run without installing
```

To install or update in `/Applications`, always remove the old bundle first — never overwrite in place:

```bash
./build-app.sh && killall ImageViewer 2>/dev/null; rm -rf /Applications/ImageViewer.app && cp -r ImageViewer.app /Applications/
```

## Swift / SwiftUI standards

- Target macOS 14 APIs; do not use symbols introduced after macOS 14 without an `#available` guard.
- Each window owns an independent `AppState` — never share state across windows.
- All disk I/O and directory scanning must run off the main thread.
- Prefer `async/await` and Swift concurrency over GCD for new code.
- Follow the existing file structure under `Sources/ImageViewer/` — views in `Views/`, helpers in `Utilities/`.

## Security scanning

- Always run `snyk_code_scan` for new or modified first-party code.
- If issues are found, fix them using the Snyk results context, then rescan.
- Repeat until no new issues remain.
- Run `snyk_sca_scan` when adding or upgrading dependencies.
