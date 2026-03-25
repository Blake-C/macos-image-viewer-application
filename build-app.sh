#!/bin/bash
set -e

APP_NAME="ImageViewer"
APP_BUNDLE="${APP_NAME}.app"

echo "Building ${APP_NAME}..."
swift build -c release 2>&1

BINARY=".build/release/${APP_NAME}"

if [ ! -f "$BINARY" ]; then
    echo "Error: binary not found at $BINARY"
    exit 1
fi

echo "Assembling ${APP_BUNDLE}..."

# Clean previous bundle
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy binary
cp "${BINARY}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Generate icon if not already present
if [ ! -f "AppIcon.icns" ]; then
    echo "Generating AppIcon.icns..."
    swift make-icon.swift
    iconutil -c icns AppIcon.iconset
fi
cp "AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

# Write Info.plist
cat > "${APP_BUNDLE}/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>ImageViewer</string>
    <key>CFBundleDisplayName</key>
    <string>Image Viewer</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.imageviewer</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>ImageViewer</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
</dict>
</plist>
EOF

echo ""
echo "Done! Built: $(pwd)/${APP_BUNDLE}"
echo ""
echo "To install:"
echo "  cp -r ${APP_BUNDLE} /Applications/"
echo ""
echo "To run now:"
echo "  open ${APP_BUNDLE}"
