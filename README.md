# WhisperKit Batch Transcriber

A native macOS application for batch transcribing audio files using WhisperKit.

## Features

- **Drag & Drop Interface**: Simply drag audio files or folders onto the app window
- **Directory Selection**: Click to browse and select a directory containing audio files
- **Batch Processing**: Transcribe multiple audio files in one go
- **Combined Output**: Automatically combines all transcriptions into a single markdown file
- **Progress Tracking**: Real-time progress indicator showing current file being processed
- **Configurable**: Set custom model path and language settings

## Requirements

- **macOS 13.0** or later
- **WhisperKit CLI** installed and available in your PATH
  - Install via: `pip install whisperkit`
  - Or follow WhisperKit installation instructions
- **Xcode 14.0+** (for building from source)

## Installation

### Option 1: Build from Source

1. Open `WhisperKitTranscriber.xcodeproj` in Xcode
2. Select your development team in Signing & Capabilities
3. Build and run (⌘R)

### Option 2: Create Release Build

See [BUILD_AND_DISTRIBUTE.md](BUILD_AND_DISTRIBUTE.md) for detailed instructions on:
- Building a distributable `.app` file
- Archiving and exporting from Xcode
- Code signing options
- Moving to Applications directory

## Usage

1. **Launch the app**
2. **Select audio files**:
   - Drag and drop audio files or folders onto the drop zone, OR
   - Click "Select Directory" to browse for a folder
3. **Configure settings** (optional):
   - Model Path: Leave empty for auto-selection, or specify a path
   - Language: Default is "en" (English)
4. **Choose output location**: Click "Choose..." to select where to save the combined markdown file
5. **Start transcription**: Click "Start Transcription"
6. **Wait for completion**: The app will process each file and show progress
7. **Access results**: Your combined transcription will be saved as a markdown file

## Supported Audio Formats

- WAV
- MP3
- M4A
- AAC
- FLAC
- OGG
- WMA

## Output Format

The app generates a single markdown file containing:

- YAML front matter with metadata (file count, creation date)
- Each transcription as a separate section with:
  - File name as heading
  - Duration (if available)
  - Full transcription text
  - Separator between files

Example output structure:
```markdown
---
combined_from: 3 files
created_utc: "2025-01-15T10:30:00Z"
format: combined_markdown
---

# Combined Audio Transcription

## audio_file_01
*Duration: 5:23*

Transcription text here...

---

## audio_file_02
...
```

## Architecture

### Components

1. **WhisperKitTranscriberApp.swift**: Main app entry point
2. **ContentView.swift**: SwiftUI interface with drop zone and controls
3. **TranscriptionManager.swift**: Core logic for:
   - Finding and loading audio files
   - Executing WhisperKit CLI commands
   - Combining transcriptions
   - Progress tracking

### How It Works

1. **File Discovery**: Recursively searches selected directory for audio files
2. **Transcription**: For each file:
   - Executes `whisperkit-cli transcribe` command
   - Parses output to extract transcription text
   - Optionally extracts duration using `ffprobe` (if available)
3. **Combination**: Merges all transcriptions into a single markdown file with proper formatting

## Troubleshooting

### WhisperKit CLI Not Found

If you see an error that WhisperKit CLI is not found:

1. Verify installation:
   ```bash
   which whisperkit-cli
   ```

2. If not found, install WhisperKit:
   ```bash
   pip install whisperkit
   ```

3. Ensure it's in your PATH:
   ```bash
   echo $PATH
   ```

### Model Path Issues

- Leave Model Path empty to let WhisperKit auto-select/download a model
- Or specify the full path to your model directory
- Default path in the app matches your script configuration

### Audio File Not Found

- Ensure audio files are in supported formats
- Check file permissions
- Try selecting a different directory

## Development

### Project Structure

```
WhisperKitTranscriber/
├── WhisperKitTranscriberApp.swift    # App entry point
├── ContentView.swift                  # Main UI
├── TranscriptionManager.swift         # Business logic
└── Info.plist                        # App metadata
```

### Building

```bash
# Open in Xcode
open WhisperKitTranscriber.xcodeproj

# Or build from command line
xcodebuild -project WhisperKitTranscriber.xcodeproj -scheme WhisperKitTranscriber -configuration Release
```

## Differences from Script Version

The app provides the same functionality as your shell scripts but with:

- **Native macOS UI**: No need to use Terminal
- **Visual Progress**: See progress in real-time
- **Easier File Selection**: Drag-and-drop or browse
- **Single Output File**: Automatically combines all transcriptions
- **Better Error Handling**: User-friendly error messages

## Future Enhancements

Potential improvements:

- [ ] Support for diarization (speaker identification)
- [ ] Export to multiple formats (JSON, SRT, TXT)
- [ ] Resume interrupted transcriptions
- [ ] Custom output templates
- [ ] Batch processing with parallel execution
- [ ] Audio preview before transcription

## License

This project is provided as-is for personal use.

## Credits

Built using:
- SwiftUI for the user interface
- WhisperKit for transcription
- Native macOS APIs for file handling

