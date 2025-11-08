# Creating the Xcode Project - Step by Step

Since the project file got corrupted, here's how to create a fresh one:

## Method 1: Create New Project in Xcode (Recommended)

1. **Open Xcode**
2. **File → New → Project**
3. **Select "macOS" tab → "App" → Next**
4. **Configure:**
   - Product Name: `WhisperKitTranscriber`
   - Team: Select your development team
   - Organization Identifier: `com.yourname` (or whatever you prefer)
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Uncheck: "Use Core Data", "Include Tests"
   - Click **Next**
5. **Save Location:**
   - Navigate to: `/Users/adam_thede/Documents/Code/Project - WhisperKit/`
   - **IMPORTANT**: Uncheck "Create Git repository" if you don't want one
   - Click **Create**

6. **Replace Default Files:**
   - In Xcode, delete the default `ContentView.swift` and `WhisperKitTranscriberApp.swift` files
   - Right-click on the `WhisperKitTranscriber` folder in Project Navigator
   - Select **"Add Files to WhisperKitTranscriber..."**
   - Navigate to: `/Users/adam_thede/Documents/Code/Project - WhisperKit/WhisperKitTranscriber/`
   - Select ALL files:
     - `WhisperKitTranscriberApp.swift`
     - `ContentView.swift`
     - `TranscriptionManager.swift`
     - `Models.swift`
     - `Info.plist`
   - Make sure **"Copy items if needed"** is checked
   - Make sure **"Add to targets: WhisperKitTranscriber"** is checked
   - Click **Add**

7. **Update Info.plist:**
   - If Xcode created a new Info.plist, you can either:
     - Replace it with the one from `WhisperKitTranscriber/Info.plist`
     - Or keep Xcode's version (it should work fine)

8. **Build Settings:**
   - Select the project in Navigator
   - Select the "WhisperKitTranscriber" target
   - Under "General" tab:
     - Minimum Deployments: macOS 13.0
   - Under "Signing & Capabilities":
     - Select your Team
     - Enable "Automatically manage signing"

9. **Build and Run:**
   - Press ⌘R or click the Play button
   - The app should build and run!

## Method 2: Use Command Line (Alternative)

If you prefer command line, you can also create a new project structure, but Method 1 is easier.

## Troubleshooting

### Files Not Showing Up?
- Make sure files are added to the target (check Target Membership in File Inspector)
- Try File → Add Files to Project again

### Build Errors?
- Check that all Swift files are included in "Compile Sources" (Build Phases)
- Make sure Info.plist is included in "Copy Bundle Resources" (Build Phases)

### Missing Imports?
- All files should compile together - if you see import errors, make sure all files are in the same target

## Project Structure Should Look Like:

```
WhisperKitTranscriber/
├── WhisperKitTranscriberApp.swift
├── ContentView.swift
├── TranscriptionManager.swift
├── Models.swift
└── Info.plist
```

All files should be visible in Xcode's Project Navigator on the left side.

