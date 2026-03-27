# Image Viewer

A fast, native macOS image gallery and viewer built with Swift and SwiftUI. No Xcode required — built entirely with Swift Package Manager from the command line.

## Features

### Gallery
- Grid view of all images in a folder with thumbnail previews
- Square or aspect-ratio thumbnail mode (toggle with **Cmd+T**)
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
- Right-click context menu with the same actions as the gallery thumbnail menu
- Trash button in the top-right corner

### Slideshow
- Press **Cmd+P** to start/stop a slideshow
- Crossfade transition between images on auto-advance; instant cut on manual navigation
- Adjustable interval (0.5s minimum) via controls overlay
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
| I | Toggle image info overlay |
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
│   ├── RootView.swift           # Top-level view switcher
│   ├── FolderPickerView.swift   # Initial folder selection screen
│   ├── GalleryView.swift        # Thumbnail grid, toolbar, filter popover
│   ├── ThumbnailCell.swift      # Individual thumbnail with context menu
│   ├── FullImageView.swift      # Full-image viewer, zoom/pan, Ken Burns, crossfade, context menu
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
- Folder changes are detected via `DispatchSource` file system events with a 0.5s debounce
- In-app deletions suppress the folder watcher to avoid redundant refreshes

## License

MIT
