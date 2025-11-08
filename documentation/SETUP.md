# Quick Setup Guide

## Prerequisites

1. **Xcode 14.0+** installed
2. **WhisperKit CLI** installed:
   ```bash
   # Recommended: Install via Homebrew
   brew install whisperkit-cli

   # Or install via pip
   pip install whisperkit

   # Verify it's in your PATH
   which whisperkit-cli
   ```

## Building the App

### Option 1: Open in Xcode (Recommended)

1. Open the project:
   ```bash
   open WhisperKitTranscriber.xcodeproj
   ```

2. In Xcode:
   - Select your development team in "Signing & Capabilities"
   - Choose a Mac as the run destination
   - Press ⌘R to build and run

### Option 2: Create New Xcode Project (If project file has issues)

1. Open Xcode
2. File → New → Project
3. Choose "macOS" → "App"
4. Product Name: `WhisperKitTranscriber`
5. Interface: SwiftUI
6. Language: Swift
7. Save in the project directory

8. Copy the Swift files:
   - `WhisperKitTranscriber/WhisperKitTranscriberApp.swift`
   - `WhisperKitTranscriber/ContentView.swift`
   - `WhisperKitTranscriber/TranscriptionManager.swift`

9. Add them to your Xcode project (drag into project navigator)

10. Update `Info.plist` if needed

## First Run

1. Launch the app
2. Verify WhisperKit CLI is found (if not, check PATH)
3. Select a directory with audio files
4. Choose output location
5. Start transcription!

## Troubleshooting

### "WhisperKit CLI not found"
- Ensure `whisperkit-cli` is installed:
  ```bash
  # Recommended: Install via Homebrew
  brew install whisperkit-cli

  # Or install via pip
  pip install whisperkit
  ```
- Check it's in PATH: `which whisperkit-cli`
- Add to PATH if needed: `export PATH=$PATH:/path/to/whisperkit`

### Build Errors
- Ensure macOS deployment target is 13.0+
- Check that all Swift files are added to target
- Clean build folder: Product → Clean Build Folder (⇧⌘K)

### Runtime Errors
- Check console for detailed error messages
- Verify audio file permissions
- Ensure output directory is writable

## Testing

Test with a small directory first:
1. Create a test folder with 2-3 audio files
2. Run transcription
3. Verify output markdown file

## Next Steps

See `README.md` for full documentation and `ARCHITECTURE.md` for technical details.

