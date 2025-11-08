# WhisperKit Transcriber - Architecture & Implementation Plan

## Overview

This document outlines the architecture and implementation plan for converting the batch WhisperKit transcription scripts into a native macOS application.

## Technology Stack

### Core Technologies
- **SwiftUI**: Modern declarative UI framework for macOS
- **Swift**: Native macOS programming language
- **AppKit**: For file dialogs and system integration
- **Process API**: For executing WhisperKit CLI commands

### Dependencies
- **WhisperKit CLI**: External command-line tool (must be installed separately)
- **ffprobe** (optional): For extracting audio duration metadata

## Architecture

### High-Level Design

```
┌─────────────────────────────────────────┐
│         SwiftUI App Window              │
│  ┌───────────────────────────────────┐  │
│  │      ContentView (UI Layer)       │  │
│  │  - Drop Zone                      │  │
│  │  - File Selection                 │  │
│  │  - Configuration Controls         │  │
│  │  - Progress Display               │  │
│  └───────────┬───────────────────────┘  │
│              │                          │
│  ┌───────────▼───────────────────────┐  │
│  │  TranscriptionManager (Logic)     │  │
│  │  - File Discovery                 │  │
│  │  - CLI Execution                  │  │
│  │  - Progress Tracking              │  │
│  │  - Markdown Combination           │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
              │
              ▼
    ┌──────────────────┐
    │ WhisperKit CLI   │
    │ (External Tool)  │
    └──────────────────┘
```

### Component Breakdown

#### 1. WhisperKitTranscriberApp.swift
**Purpose**: Application entry point
- Defines the main app structure
- Configures window properties
- Sets up the app lifecycle

**Key Features**:
- `@main` entry point
- Window configuration (hidden title bar, fixed size)

#### 2. ContentView.swift
**Purpose**: User interface layer
- Displays the main window
- Handles user interactions
- Manages UI state

**Key Features**:
- **Drop Zone**:
  - Visual drop target with dashed border
  - Supports drag-and-drop of files/folders
  - Shows file count when files are selected
- **File Selection**:
  - "Select Directory" button opens NSOpenPanel
  - Recursively finds all audio files
- **Configuration**:
  - Model path input (optional)
  - Language selection (default: "en")
- **Output Selection**:
  - NSSavePanel for choosing output location
  - Shows selected filename
- **Progress Display**:
  - Linear progress bar
  - Status message showing current file
- **Action Button**:
  - "Start Transcription" button
  - Disabled during processing
  - Shows spinner when active

#### 3. TranscriptionManager.swift
**Purpose**: Core business logic
- Manages transcription state
- Coordinates file processing
- Handles CLI execution

**Key Responsibilities**:

1. **File Management**:
   - `loadAudioFiles(from:)`: Loads files from directory
   - `findAudioFiles(in:)`: Recursively searches for audio files
   - `isAudioFile(_:)`: Validates file extensions

2. **CLI Integration**:
   - `findWhisperKitCLI()`: Locates whisperkit-cli in PATH
   - `transcribeFile(_:tempDir:)`: Executes transcription command
   - Parses CLI output to extract transcription text

3. **Metadata Extraction**:
   - `getAudioDuration(_:)`: Uses ffprobe to get duration
   - `findFFProbe()`: Locates ffprobe utility

4. **Output Generation**:
   - `combineTranscriptions(_:outputPath:)`: Merges all transcriptions
   - Formats markdown with YAML front matter
   - Adds file sections with metadata

5. **State Management**:
   - `@Published` properties for SwiftUI binding
   - Progress tracking (0.0 to 1.0)
   - Error handling with user-friendly messages

## Data Flow

### Transcription Workflow

```
1. User selects directory
   ↓
2. TranscriptionManager.findAudioFiles()
   - Recursively searches directory
   - Filters by audio extensions
   - Sorts alphabetically
   ↓
3. User clicks "Start Transcription"
   ↓
4. For each audio file:
   a. TranscriptionManager.transcribeFile()
      - Creates Process with whisperkit-cli
      - Executes: whisperkit-cli transcribe --audio-path <file> --language <lang>
      - Parses output to extract text
      - Optionally gets duration via ffprobe
   b. Stores TranscriptionResult
   c. Updates progress (index / total)
   ↓
5. TranscriptionManager.combineTranscriptions()
   - Creates markdown with YAML front matter
   - Adds each transcription as section
   - Writes to output file
   ↓
6. Show success alert
```

### File Processing Details

**CLI Command Structure**:
```bash
whisperkit-cli transcribe \
  --audio-path "/path/to/file.wav" \
  --language "en" \
  [--model-path "/path/to/model"] \
  --verbose
```

**Output Parsing**:
- CLI outputs: "Transcription of <file>:\n<text>"
- Extract text after "Transcription of" line
- Trim whitespace

**Markdown Format**:
```markdown
---
combined_from: 3 files
created_utc: "2025-01-15T10:30:00Z"
format: combined_markdown
---

# Combined Audio Transcription

## filename_01
*Duration: 5:23*

Transcription text...

---

## filename_02
...
```

## Error Handling

### Error Types
1. **WhisperKitNotFound**: CLI not in PATH
   - User-friendly message with installation instructions

2. **TranscriptionFailed**: CLI execution error
   - Shows error output from CLI
   - Continues with next file (non-fatal)

3. **File Errors**: Missing files, permissions
   - Validates before processing
   - Shows specific error messages

### Error Display
- SwiftUI `.alert()` modifiers
- Non-blocking (allows user to continue)
- Clear, actionable error messages

## UI/UX Design

### Visual Design
- **Window Size**: Fixed 600px width, auto height
- **Drop Zone**:
  - Large, clearly visible area
  - Visual feedback on drag-over (highlight)
  - Icon and text instructions
- **Progress**:
  - Linear progress bar
  - Status text below
  - Non-intrusive

### User Flow
1. Launch app → See empty drop zone
2. Drag files OR click "Select Directory"
3. See file count update
4. (Optional) Configure model/language
5. Choose output location
6. Click "Start Transcription"
7. Watch progress
8. Get success notification with file location

## Performance Considerations

### Processing Strategy
- **Sequential Processing**: One file at a time
  - Simpler error handling
  - Predictable memory usage
  - Clear progress indication

- **Future Enhancement**: Parallel processing
  - Could process multiple files simultaneously
  - Requires careful resource management

### Memory Management
- Temporary files cleaned up after use
- Large files processed one at a time
- No caching of transcriptions (stream to output)

## Security & Permissions

### File Access
- User explicitly selects directories/files
- No automatic file system access
- Respects macOS privacy settings

### CLI Execution
- Only executes whisperkit-cli (validated path)
- No arbitrary command execution
- Process isolation

## Testing Strategy

### Unit Tests (Future)
- File discovery logic
- Markdown formatting
- Error handling

### Integration Tests (Future)
- CLI execution with mock files
- End-to-end transcription workflow

### Manual Testing
- Test with various audio formats
- Test with nested directories
- Test error scenarios (missing CLI, invalid files)

## Future Enhancements

### Phase 2 Features
1. **Diarization Support**
   - Integrate with diarization server
   - Add speaker labels to output
   - UI toggle for enabling

2. **Multiple Output Formats**
   - JSON export
   - SRT subtitle files
   - Individual file outputs

3. **Resume Capability**
   - Save progress state
   - Skip already-transcribed files
   - Resume from interruption

4. **Advanced Configuration**
   - Custom output templates
   - Batch size configuration
   - Parallel processing option

5. **UI Improvements**
   - File list preview
   - Audio preview before transcription
   - Dark mode support
   - Window resizing

## Comparison with Script Version

### Advantages of App
- ✅ Native macOS UI (no Terminal needed)
- ✅ Visual progress indication
- ✅ Drag-and-drop convenience
- ✅ Better error messages
- ✅ Single combined output (automatic)
- ✅ No manual script editing

### Script Advantages
- ✅ More flexible (easy to customize)
- ✅ Can be automated/scripted
- ✅ Supports advanced features (diarization server, JSON export)
- ✅ No compilation needed

### Migration Path
- Scripts remain available for advanced users
- App provides simpler workflow for common use case
- Can add script features to app incrementally

## Build & Deployment

### Development Build
```bash
# Open in Xcode
open WhisperKitTranscriber.xcodeproj

# Build and run
⌘R
```

### Release Build
1. Product → Archive in Xcode
2. Distribute App from Organizer
3. Export as .app bundle or .dmg

### Distribution Options
- **Direct Distribution**: Share .app bundle
- **DMG**: Create disk image for distribution
- **App Store**: Requires code signing and review (future)

## Dependencies

### External Tools (Required)
- **whisperkit-cli**: Must be installed and in PATH
  - Install: `pip install whisperkit`
  - Verify: `which whisperkit-cli`

### External Tools (Optional)
- **ffprobe**: For audio duration extraction
  - Part of FFmpeg
  - Install: `brew install ffmpeg`

## Configuration

### Default Settings
- **Model Path**: Pre-filled with user's model path (from script)
- **Language**: "en" (English)
- **Output Format**: Markdown with YAML front matter

### User Customization
- Model path can be cleared for auto-selection
- Language can be changed
- Output location chosen per session

## Conclusion

This architecture provides a clean separation of concerns:
- **UI Layer**: SwiftUI for modern, responsive interface
- **Logic Layer**: TranscriptionManager for business logic
- **External Layer**: WhisperKit CLI for actual transcription

The design is extensible and can grow to include additional features like diarization, multiple output formats, and advanced configuration options.

