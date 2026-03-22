# SelectToCopy

A lightweight macOS menu bar app that automatically copies selected text to your clipboard.

## Features

- Auto-copy selected text from focused apps
- Deduplicates clipboard writes (avoids re-copying the same text)
- Menu bar controls for permissions and app lifecycle
- Optional **Start at Login** toggle (macOS 13+)

## Install (Homebrew)

```bash
brew tap hindraxxx/tap
brew install --cask hindraxxx/tap/select-to-copy
```

If you already have an existing app at `/Applications/SelectToCopy.app`, either remove it first or install to your user Applications folder:

```bash
brew install --cask hindraxxx/tap/select-to-copy --appdir="$HOME/Applications"
```

## First Launch Setup

1. Launch the app.
2. Open `System Settings > Privacy & Security > Accessibility`.
3. Enable **SelectToCopy**.
4. Click the menu bar icon and run **Check Accessibility Permissions** once.

Without Accessibility permission, the app will run in limited mode and will not capture selections.

## Usage

- Select text in a supported app (TextEdit, browser inputs, chat/note apps).
- The selected text is copied automatically.
- Paste anywhere with `Cmd+V`.

## Build From Source

```bash
swift build
swift run SelectToCopy
```

Note: when running with `swift run`, macOS may request Accessibility permission for your terminal app (Terminal/iTerm/Warp) instead of `SelectToCopy`.

## Package a .app and .dmg Locally

```bash
swift build -c release
mkdir -p dist/SelectToCopy.app/Contents/MacOS
cp .build/arm64-apple-macosx/release/SelectToCopy dist/SelectToCopy.app/Contents/MacOS/SelectToCopy
cp Sources/SelectToCopy/Resources/Info.plist dist/SelectToCopy.app/Contents/Info.plist
codesign --force --deep --sign - dist/SelectToCopy.app

mkdir -p dist/dmg-root
cp -R dist/SelectToCopy.app dist/dmg-root/
hdiutil create -volname "SelectToCopy" -srcfolder dist/dmg-root -ov -format UDZO dist/SelectToCopy-macos-arm64.dmg
```

## Release

- App releases: `https://github.com/hindraxxx/select-to-copy/releases`
- Homebrew tap: `https://github.com/hindraxxx/homebrew-tap`
