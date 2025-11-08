# Building and Distributing the App

This guide explains how to build a distributable `.app` file that you can use in your Applications directory.

## Quick Build (For Personal Use)

### Method 1: Build and Copy from Xcode

1. **Open the project** in Xcode:
   ```
   Open: WhisperKit Transcriber/WhisperKit Transcriber.xcodeproj
   ```

2. **Select the scheme**:
   - In the toolbar, make sure "WhisperKit Transcriber" is selected
   - Select "My Mac" as the destination (not a simulator)

3. **Build the app**:
   - Press `⌘B` (Product → Build)
   - Or use `⌘R` to build and run

4. **Locate the built app**:
   - In Xcode, go to **Product → Show Build Folder in Finder**
   - Navigate to: `Build/Products/Debug/WhisperKit Transcriber.app`
   - Or use: `⌘⇧⌥K` to clean build folder, then `⌘B`, then right-click the app in Products and "Show in Finder"

5. **Copy to Applications**:
   - Drag `WhisperKit Transcriber.app` to your `/Applications` folder
   - Or copy it anywhere you want to use it

### Method 2: Archive and Export (Recommended for Distribution)

1. **Open the project** in Xcode

2. **Select "Any Mac"** as the destination in the toolbar

3. **Create an Archive**:
   - Go to **Product → Archive**
   - Wait for the archive to complete (may take a minute)

4. **Export the App**:
   - The Organizer window will open automatically
   - Click **"Distribute App"**
   - Select **"Copy App"** (for personal use) or **"Developer ID"** (if you have a paid developer account)
   - Click **"Next"**
   - Choose a location to save the `.app` file
   - Click **"Export"**

5. **Move to Applications**:
   - The exported `.app` file will be in the location you chose
   - Drag it to `/Applications` or wherever you want it

## Building from Command Line

You can also build from the terminal:

```bash
# Navigate to project directory
cd "WhisperKit Transcriber"

# Build the app
xcodebuild -project "WhisperKit Transcriber.xcodeproj" \
           -scheme "WhisperKit Transcriber" \
           -configuration Release \
           -derivedDataPath ./build

# The app will be at:
# ./build/Build/Products/Release/WhisperKit Transcriber.app
```

## Code Signing

### For Personal Use (No Signing)

If you're just using it yourself, you can run unsigned apps:

1. Build the app as described above
2. When you first try to run it, macOS may show a security warning
3. Go to **System Settings → Privacy & Security**
4. Click **"Open Anyway"** next to the security message

### For Distribution (Code Signing)

If you want to distribute the app or avoid security warnings:

1. **Get a Developer ID** (requires Apple Developer Program membership - $99/year)
2. In Xcode:
   - Select the project in the navigator
   - Select the "WhisperKit Transcriber" target
   - Go to **Signing & Capabilities**
   - Check **"Automatically manage signing"**
   - Select your **Team**
   - Xcode will handle code signing automatically

## Notarization (Optional)

For distribution outside the Mac App Store, you may want to notarize:

1. Archive the app (Product → Archive)
2. Export with "Developer ID" option
3. Use `notarytool` or `altool` to submit for notarization
4. This is only needed if distributing to others

## Troubleshooting

### "App is damaged" error

If you get this error:
1. Right-click the app → **Open**
2. Or run: `xattr -cr "WhisperKit Transcriber.app"` in Terminal

### App won't launch

- Check Console.app for error messages
- Make sure WhisperKit CLI is installed: `which whisperkit-cli`
- Try running from Terminal: `open "WhisperKit Transcriber.app"`

### Build errors

- Clean build folder: `⌘⇧K`
- Delete DerivedData: `rm -rf ~/Library/Developer/Xcode/DerivedData`
- Rebuild: `⌘B`

## File Size

The built `.app` file should be relatively small (typically 5-15 MB) since it doesn't bundle WhisperKit - it uses the system-installed `whisperkit-cli`.

## Dependencies

Remember: The app requires `whisperkit-cli` to be installed separately:
```bash
# Recommended: Install via Homebrew
brew install whisperkit-cli

# Or install via pip
pip install whisperkit
```

The app will automatically find it in your PATH.

