# Image Viewer

A fast, native macOS image gallery and viewer built with Swift and SwiftUI. No Xcode required — built entirely with Swift Package Manager from the command line.

> **Note:** This application was written entirely by [Claude](https://claude.ai) (Anthropic) and has not been reviewed by a human developer. Use at your own discretion.

## Features

### Gallery
- Grid view of all images in a folder with thumbnail previews
- Square or aspect-ratio thumbnail mode (toggle with **Cmd+T**)
- Masonry layout mode — variable-height columns sized to each image's natural aspect ratio
- Sort by name, date modified, or file size (ascending or descending)
- Search by filename (**Cmd+S** to focus search field)
- Filter by file type (JPEG, PNG, HEIC, etc.)
- Filter by date range (modified date)
- Favorites — star images and filter to show only favorites
- Multi-select with **Cmd+click** (individual) or **Shift+click** (range)
- Remembers your sort, filters, and view settings per folder
- Auto-refreshes when files are added, removed, or renamed in the folder

### Full-Image View
- Click any thumbnail to open the full image
- Smooth zoom with scroll wheel, **Cmd++** / **Cmd+-**, or **Cmd+1** (actual pixels)
- Pan by dragging
- **Cmd+0** to reset zoom to fit
- Arrow keys to navigate between images (or pan when zoomed in)
- Image info overlay (**I**) — filename, pixel dimensions, file size, date modified
- Metadata sheet (**M**) — full ImageIO metadata (General, TIFF, EXIF, GPS, IPTC, PNG); ComfyUI workflow images show parsed model, generation, and prompt sections; every field has a copy-to-clipboard button
- Right-click context menu with the same actions as the gallery thumbnail menu
- Play/pause slideshow button in the top-right corner (**Cmd+P**)
- Trash button in the top-right corner

### Slideshow
- Press **Cmd+P** to start/stop a slideshow (or use the play/pause button in the full-image toolbar)
- Crossfade transition between images on auto-advance; instant cut on manual navigation
- Adjustable interval (0.5s minimum) via controls overlay
- Shuffle mode — randomly selects the next image instead of advancing sequentially
- Ken Burns pan & zoom effect — portrait images pan top-to-bottom, landscape pan left-to-right

### Delete / Trash
- **Cmd+Delete** moves the current image to Trash (gallery and full-image view)
- Trash button in the top-right of the full-image view
- Multi-select trash via the action bar in the gallery
- Plays the system trash sound on deletion
- In-app deletions do not trigger an unnecessary folder refresh

### Multi-select Actions
- Move selected images to Trash
- Copy file paths to clipboard

### Thumbnail Context Menu (right-click)
- Open in default app
- Show in Finder
- Add/remove from Favorites
- Copy image to clipboard
- Copy file path
- Set as desktop wallpaper
- Move to Trash

### Full-Image Context Menu (right-click)
- Same actions as the thumbnail context menu

### Folder Security
- Lock any open folder with Touch ID via the gear icon in the gallery toolbar
- Authentication is required each time a locked folder is opened — including on app launch
- Falls back to your macOS login password if Touch ID is unavailable
- Lock state is stored per-folder in UserDefaults and enforced via macOS LocalAuthentication
- Disabling a lock requires Touch ID or your login password
- Locked folders show a lock icon in the toolbar gear button

### General
- Multiple independent windows (**Cmd+N**), each with its own folder and state
- Full-screen support (**Cmd+F**)
- Refresh folder (**Cmd+R**)
- Open folder (**Cmd+O**)
- Remembers the last opened folder across launches
- Per-folder settings persistence (sort, filters, thumbnail mode)
- Window title bar shows folder name, image count, and total file size — updates live

## Supported Formats

`jpg` `jpeg` `png` `gif` `heic` `heif` `tiff` `tif` `bmp` `webp` `avif`

## Requirements

- macOS 14 (Sonoma) or later
- Xcode Command Line Tools **or** a full Xcode install (for the Swift compiler)

Install command line tools if needed:
```bash
xcode-select --install
```

## Building

Clone the repository and run the build script from the project root:

```bash
git clone <repo-url>
cd image-viewer-gallery
./build-app.sh
```

This compiles a release build and produces `ImageViewer.app` in the project directory.

### Install to /Applications

Always remove the old bundle before copying — overwriting in place can cause macOS to cache the old binary or code signature:

```bash
rm -rf /Applications/ImageViewer.app
cp -r ImageViewer.app /Applications/
```

If macOS shows a security warning the first time you open the app, right-click `ImageViewer.app` and choose **Open**, then confirm. This is expected for apps distributed outside the Mac App Store.

After installation, refresh the Launch Services database so the app appears correctly in Spotlight and Launchpad:

```bash
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -r -domain local -domain system -domain user && killall Finder
```

### Updating the app

If a newly built version doesn't reflect your latest changes, macOS likely cached the old bundle. Quit the app first, then do a clean replace:

```bash
./build-app.sh && killall ImageViewer 2>/dev/null; rm -rf /Applications/ImageViewer.app && cp -r ImageViewer.app /Applications/
```

The `killall` step ensures the old process isn't still holding the bundle open. The `rm -rf` before copying is the critical part — never overwrite a running or previously-installed `.app` in place.

### Run without installing

```bash
open ImageViewer.app
```

Or run directly from the terminal (prints logs to stdout):

```bash
.build/release/ImageViewer
```

### Rebuilding the app icon

The app icon is pre-generated and included in the repo (`AppIcon.icns`). If you want to regenerate it:

```bash
swift make-icon.swift
iconutil -c icns AppIcon.iconset
```

## Keyboard Shortcuts

### Gallery
| Shortcut | Action |
|---|---|
| Arrow keys | Navigate thumbnails |
| Enter / Space | Open selected image |
| Cmd+Delete | Move selected image to Trash |
| Cmd+S | Focus search field |
| Cmd+T | Toggle square / aspect-ratio thumbnails |
| Cmd+O | Open folder |
| Cmd+R | Refresh folder |
| Cmd+N | New window |
| Cmd+F | Toggle full screen |
| Escape | Clear multi-selection / clear search |

### Full-Image View
| Shortcut | Action |
|---|---|
| ← → | Previous / next image (or pan when zoomed) |
| ↑ ↓ | Pan up / down |
| Scroll wheel | Zoom in / out at cursor |
| Cmd++ / Cmd+- | Zoom in / out |
| Cmd+0 | Reset zoom to fit |
| Cmd+1 | Zoom to actual pixels (1:1) |
| F | Toggle favorite |
| I | Toggle image info overlay |
| M | Open metadata sheet |
| Cmd+P | Start / stop slideshow |
| Cmd+Delete | Move current image to Trash |
| Cmd+S | Return to gallery and focus search |
| Cmd+O | Open folder |
| Escape / Enter / Space | Return to gallery |
| Cmd+R | Refresh folder |

### Search Field
| Shortcut | Action |
|---|---|
| Cmd+S | Focus search field |
| Escape | Clear search text (first press) / defocus (second press) |

## Project Structure

```
Sources/ImageViewer/
├── AppState.swift               # Central state, navigation, sort, filter, slideshow, folder watching
├── ImageViewerApp.swift         # App entry point, per-window setup, menu commands, title bar
├── Views/
│   ├── RootView.swift           # Top-level view switcher, folder auth gate
│   ├── FolderPickerView.swift   # Initial folder selection screen, auth failure UI
│   ├── GalleryView.swift        # Thumbnail grid, masonry layout, toolbar, filter popover
│   ├── ThumbnailCell.swift      # Individual thumbnail with context menu (grid + masonry)
│   ├── FullImageView.swift      # Full-image viewer, zoom/pan, Ken Burns, crossfade, context menu
│   ├── MetadataPanelView.swift  # Full ImageIO + ComfyUI metadata sheet
│   ├── SlideshowControlsOverlay.swift
│   ├── InfoOverlayView.swift    # Image metadata HUD
│   └── FolderSettingsSheet.swift  # Touch ID lock toggle
└── Utilities/
    ├── ImageLoader.swift            # Async image loading with LRU thumbnail cache
    ├── FolderScanner.swift          # Async directory enumeration
    ├── FolderLockManager.swift      # Keychain-backed Touch ID lock state
    └── ComfyUIWorkflowParser.swift  # Parses ComfyUI workflow JSON embedded in PNG metadata
```

## Technical Notes

- Built with **SwiftUI + AppKit** on **Swift Package Manager** — no Xcode project file
- Minimum deployment target: **macOS 14**
- Thumbnail loading is fully asynchronous with an in-memory LRU cache (400 entries)
- Directory scanning runs off the main thread to avoid UI freezes on large folders
- Each window owns an independent `AppState` object — windows don't share state
- Per-folder settings are stored in `UserDefaults` as JSON, decoded once per launch and cached in memory
- Folder changes are detected via `DispatchSource` file system events with a 0.5s debounce
- In-app deletions suppress the folder watcher to avoid redundant refreshes
- Folder lock state is stored in `UserDefaults`; authentication is enforced via `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` which gates access with Touch ID or the macOS login password

## License

MIT
