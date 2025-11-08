# Project Structure

This document explains the organization of the WhisperKit Transcriber project.

## Directory Structure

```
Project - WhisperKit/
├── WhisperKit Transcriber/          # Active Xcode project
│   ├── WhisperKit Transcriber/     # Source code and assets
│   │   ├── Assets.xcassets/        # App icons and colors
│   │   ├── AudioPlayerManager.swift
│   │   ├── ContentView.swift
│   │   ├── Models.swift
│   │   ├── TranscriptionManager.swift
│   │   └── WhisperKit_TranscriberApp.swift
│   └── WhisperKit Transcriber.xcodeproj/  # Xcode project file
│
├── documentation/                   # All documentation files
│   ├── ARCHITECTURE.md
│   ├── CREATE_XCODE_PROJECT.md
│   ├── DIARIZATION_SETUP.md
│   ├── ICON_SETUP.md
│   ├── NEXT_STEPS.md
│   ├── PROJECT_STRUCTURE.md (this file)
│   ├── README.md
│   ├── SETUP.md
│   ├── UX_DESIGN.md
│   └── UX_IMPROVEMENTS.md
│
└── legacy-assets/                   # Development artifacts and old files
    ├── WhisperKitTranscriber/       # Old project structure
    ├── WhisperKitTranscriber.xcodeproj/  # Old Xcode project
    ├── app-icon.svg                 # Source SVG for app icon
    ├── combine_transcriptions.sh   # Original bash script
    ├── diarization_server.py        # Diarization server (not currently used)
    ├── requirements-diarization.txt # Python dependencies for diarization
    ├── setup_diarization.sh         # Diarization setup script
    └── transcribe_here.sh           # Original bash script
```

## Active Project Files

The active Xcode project is located in:
- **Project Root**: `WhisperKit Transcriber/`
- **Xcode Project**: `WhisperKit Transcriber/WhisperKit Transcriber.xcodeproj`
- **Source Code**: `WhisperKit Transcriber/WhisperKit Transcriber/`

## Documentation

All documentation files are in the `documentation/` directory:
- **README.md**: User guide and overview
- **SETUP.md**: Quick setup instructions
- **ARCHITECTURE.md**: Technical architecture details
- **UX_DESIGN.md**: UI/UX design decisions
- **ICON_SETUP.md**: Instructions for app icon setup

## Legacy Assets

Files in `legacy-assets/` are kept for reference but are not part of the active build:
- Original bash scripts (`transcribe_here.sh`, `combine_transcriptions.sh`)
- Old Xcode project structure (`WhisperKitTranscriber/`)
- Diarization server files (not currently integrated)
- Source SVG icon file (PNG versions are in Assets.xcassets)

## Building the Project

To build and run the app:
1. Open `WhisperKit Transcriber/WhisperKit Transcriber.xcodeproj` in Xcode
2. Select your target device/simulator
3. Press ⌘R to build and run

