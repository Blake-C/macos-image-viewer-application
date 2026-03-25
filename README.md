# Image Viewer

A fast, native macOS image gallery and viewer built with Swift and SwiftUI. No Xcode required — built entirely with Swift Package Manager from the command line.

## Features

### Gallery
- Grid view of all images in a folder with thumbnail previews
- Square or aspect-ratio thumbnail mode (toggle with **Cmd+T**)
- Sort by name, date modified, or file size (ascending or descending)
- Search by filename
- Filter by file type (JPEG, PNG, HEIC, etc.)
- Filter by date range (modified date)
- Favorites — star images and filter to show only favorites
- Multi-select with **Cmd+click** (individual) or **Shift+click** (range)
- Remembers your sort, filters, and view settings per folder

### Full-Image View
- Click any thumbnail to open the full image
- Smooth zoom with scroll wheel, **Cmd++** / **Cmd+-**, or **Cmd+1** (actual pixels)
- Pan by dragging
- **Cmd+0** to reset zoom to fit
- Arrow keys to navigate between images (or pan when zoomed in)
- Image info overlay (**I**) — filename, pixel dimensions, file size, date modified

### Slideshow
- Press **Space** to start/stop a slideshow
- Crossfade transition between images on auto-advance; instant cut on manual navigation
- Adjustable interval (0.5s minimum)
- Ken Burns pan & zoom effect — portrait images pan top-to-bottom, landscape pan left-to-right

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

### General
- Multiple independent windows (**Cmd+N**), each with its own folder and state
- Full-screen support (**Cmd+F**)
- Refresh folder to pick up new/removed files (**Cmd+R**)
- Remembers the last opened folder across launches
- Per-folder settings persistence (sort, filters, thumbnail mode)

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
cd image-viewer-galler
./build-app.sh
```

This compiles a release build and produces `ImageViewer.app` in the project directory.

### Install to /Applications

```bash
cp -r ImageViewer.app /Applications/
```

If macOS shows a security warning the first time you open the app, right-click `ImageViewer.app` and choose **Open**, then confirm. This is expected for apps distributed outside the Mac App Store.

After installation, refresh the Launch Services database so the app appears correctly in Spotlight and Launchpad:

```bash
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -r -domain local -domain system -domain user && killall Finder
```

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
| Enter | Open selected image |
| Cmd+T | Toggle square / aspect-ratio thumbnails |
| Cmd+O | Open folder |
| Cmd+R | Refresh folder |
| Cmd+N | New window |
| Cmd+F | Toggle full screen |
| Escape | Clear multi-selection |

### Full-Image View
| Shortcut | Action |
|---|---|
| ← → | Previous / next image (or pan when zoomed) |
| ↑ ↓ | Pan up / down |
| Scroll wheel | Zoom in / out at cursor |
| Cmd++ / Cmd+- | Zoom in / out |
| Cmd+0 | Reset zoom to fit |
| Cmd+1 | Zoom to actual pixels (1:1) |
| I | Toggle image info overlay |
| Space | Start / stop slideshow |
| Escape / Click | Return to gallery (when at fit zoom) |
| Cmd+R | Refresh folder |

## Project Structure

```
Sources/ImageViewer/
├── AppState.swift               # Central state, navigation, sort, filter, slideshow
├── ImageViewerApp.swift         # App entry point, per-window setup, menu commands
├── Views/
│   ├── RootView.swift           # Top-level view switcher
│   ├── FolderPickerView.swift   # Initial folder selection screen
│   ├── GalleryView.swift        # Thumbnail grid, toolbar, filter popover
│   ├── ThumbnailCell.swift      # Individual thumbnail with context menu
│   ├── FullImageView.swift      # Full-image viewer, zoom/pan, Ken Burns, crossfade
│   ├── SlideshowControlsOverlay.swift
│   └── InfoOverlayView.swift    # Image metadata HUD
└── Utilities/
    ├── ImageLoader.swift        # Async image loading with LRU thumbnail cache
    └── FolderScanner.swift      # Async directory enumeration
```

## Technical Notes

- Built with **SwiftUI + AppKit** on **Swift Package Manager** — no Xcode project file
- Minimum deployment target: **macOS 14**
- Thumbnail loading is fully asynchronous with an in-memory LRU cache (400 entries)
- Directory scanning runs off the main thread to avoid UI freezes on large folders
- Each window owns an independent `AppState` object — windows don't share state
- Per-folder settings are stored in `UserDefaults` as JSON, decoded once per launch and cached in memory

## License

MIT
