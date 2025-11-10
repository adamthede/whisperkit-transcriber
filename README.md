# WhisperKit Batch Transcriber

A native macOS application for batch transcribing audio files using WhisperKit.

## Features

- **Drag & Drop Interface**: Simply drag audio files or folders onto the app window
- **Directory Selection**: Click to browse and select a directory containing audio files
- **Batch Processing**: Transcribe multiple audio files in one go
- **Speaker Diarization**: Identify and label different speakers in audio (NEW!)
- **Combined Output**: Automatically combines all transcriptions into a single markdown file
- **Multiple Export Formats**: Export to Markdown, Plain Text, JSON, or individual files
- **Progress Tracking**: Real-time progress indicator showing current file being processed
- **Configurable**: Set custom model path, language settings, and diarization options

## Requirements

- **macOS 13.0** or later
- **WhisperKit CLI** installed and available in your PATH
  - Install via Homebrew (recommended): `brew install whisperkit-cli`
  - Or via pip: `pip install whisperkit`
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
   - Model: Choose a WhisperKit model or use auto-selection
   - Language: Default is "en" (English)
   - **Speaker Diarization**: Enable to identify different speakers (requires diarization server)
4. **Start transcription**: Click "Start Transcription"
5. **Wait for completion**: The app will process each file and show progress
6. **Assign speaker names** (if diarization is enabled):
   - Select a transcription from the results
   - Click "Set Name" or "Edit" for each speaker
   - Enter meaningful names (e.g., "John Smith", "Interviewer")
7. **Export results**: Choose your preferred format and export location
   - Markdown (combined or individual files)
   - Plain Text
   - JSON with full segment data
   - Individual files (one per audio file)

### Speaker Diarization

To use speaker diarization:

1. Set up a diarization server (see [SPEAKER_DIARIZATION.md](SPEAKER_DIARIZATION.md))
2. Enable "Speaker Diarization" in Configuration
3. Configure the server URL (default: http://localhost:50061/diarize)
4. Transcribe as usual - speaker labels will be added automatically

For detailed instructions, troubleshooting, and server setup, see the [Speaker Diarization Documentation](SPEAKER_DIARIZATION.md).

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
   # Recommended: Install via Homebrew
   brew install whisperkit-cli

   # Or install via pip
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

## Future Enhancements

Potential improvements:

- [x] Support for diarization (speaker identification) - **IMPLEMENTED**
- [x] Export to multiple formats (JSON, TXT, Markdown) - **IMPLEMENTED**
- [ ] Export to subtitle formats (SRT, VTT)
- [ ] Resume interrupted transcriptions
- [ ] Custom output templates
- [ ] Batch processing with parallel execution
- [ ] Audio preview before transcription
- [ ] Visual speaker timeline
- [ ] Speaker statistics (speaking time, word count)
- [ ] Filter/search by speaker

## License

This project is provided as-is for personal use.

## Credits

Built using:
- SwiftUI for the user interface
- WhisperKit for transcription
- Native macOS APIs for file handling

