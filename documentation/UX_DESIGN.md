# UX Design Document - WhisperKit Transcriber

## User Journey Analysis

### Current Flow
1. Select files → Configure → Choose output → Transcribe → Done (alert)

### Problems with Current Flow
- ❌ No preview of transcriptions before export
- ❌ Can't see individual file results
- ❌ Model selection is manual text entry
- ❌ Single export format (markdown only)
- ❌ No way to review/edit before saving
- ❌ Output location chosen upfront (before seeing results)

### Improved Flow
1. **Setup Phase**: Select files → Configure model → Start transcription
2. **Processing Phase**: Watch progress → See transcriptions appear in real-time
3. **Review Phase**: Preview transcriptions → Edit if needed
4. **Export Phase**: Choose format → Choose location → Export

## Proposed UI Layout

### Option A: Two-Pane Layout (Recommended)
```
┌─────────────────────────────────────────────────────┐
│  WhisperKit Batch Transcriber                       │
├──────────────────────┬──────────────────────────────┤
│                      │                              │
│  INPUT & CONFIG      │  RESULTS & PREVIEW           │
│                      │                              │
│  [Drop Zone]         │  [Transcription List]        │
│  [File List]         │  [Selected Transcription]    │
│  [Model Selector]    │  [Edit/Preview Area]         │
│  [Language]          │  [Export Options]            │
│  [Start Button]      │  [Export Button]             │
│                      │                              │
└──────────────────────┴──────────────────────────────┘
```

### Option B: Tab-Based Layout
```
┌─────────────────────────────────────────────────────┐
│  [Setup] [Processing] [Results]                     │
├─────────────────────────────────────────────────────┤
│                                                      │
│  Content changes based on active tab                 │
│                                                      │
└─────────────────────────────────────────────────────┘
```

### Option C: Single View with Expandable Sections (Simpler)
```
┌─────────────────────────────────────────────────────┐
│  [Drop Zone / File Selection]                       │
│  [Configuration (Expandable)]                        │
│  [Transcription Results (Expandable)]                │
│  [Export Options]                                    │
└─────────────────────────────────────────────────────┘
```

## Feature Breakdown

### 1. Model Selection

**Current**: Text field for model path

**Improved**:
- **Dropdown/Picker** with common models:
  - "Auto-select (Recommended)"
  - "tiny" (39MB, fastest, lowest quality)
  - "base" (74MB, fast, good quality)
  - "small" (244MB, balanced)
  - "medium" (769MB, high quality)
  - "large-v3" (1550MB, best quality)
  - "Custom Path..." (opens file browser)

- **Model Info Display**:
  - Show model size
  - Show quality vs speed trade-off
  - Show download status if not cached

**Implementation**:
```swift
enum WhisperModel: String, CaseIterable {
    case auto = "auto"
    case tiny = "tiny"
    case base = "base"
    case small = "small"
    case medium = "medium"
    case largeV3 = "large-v3"
    case custom = "custom"

    var displayName: String {
        switch self {
        case .auto: return "Auto-select (Recommended)"
        case .tiny: return "Tiny (39MB) - Fastest"
        case .base: return "Base (74MB) - Fast"
        case .small: return "Small (244MB) - Balanced"
        case .medium: return "Medium (769MB) - High Quality"
        case .largeV3: return "Large v3 (1550MB) - Best Quality"
        case .custom: return "Custom Path..."
        }
    }
}
```

### 2. Transcription Preview

**Features**:
- **List View**: Show all completed transcriptions
  - File name
  - Duration
  - Status (✓ Complete, ⏳ Processing, ❌ Error)
  - Preview snippet

- **Detail View**: When file selected
  - Full transcription text
  - Editable text area
  - Metadata (duration, model used, timestamp)
  - Individual export button

- **Real-time Updates**: As files complete, add to list

**UI Component**:
```swift
List {
    ForEach(transcriptionManager.completedTranscriptions) { transcription in
        TranscriptionRow(transcription: transcription)
            .onTapGesture {
                selectedTranscription = transcription
            }
    }
}
```

### 3. Export Options

**Current**: Single markdown file, chosen upfront

**Improved**:
- **Format Selection**:
  - Markdown (combined)
  - Plain Text (combined)
  - JSON (structured data)
  - Individual Files (one per audio file)
  - SRT (subtitles, if timestamps available)

- **Export Button**:
  - Only enabled when transcriptions complete
  - Shows format picker
  - Opens save dialog
  - Can export multiple formats at once

- **Quick Actions**:
  - "Copy to Clipboard" button
  - "Open in Finder" after export
  - "Share" menu

### 4. Enhanced File Selection

**Current**: Simple count display

**Improved**:
- **File List View**:
  - Show all selected files
  - File name, size, duration (if available)
  - Remove individual files
  - Sort options
  - Filter by format

- **Status Indicators**:
  - Pending
  - Processing
  - Complete
  - Error

## Recommended Implementation: Option C (Simplest, Most Practical)

### Layout Structure

```
┌─────────────────────────────────────────────────────┐
│  WhisperKit Batch Transcriber                       │
├─────────────────────────────────────────────────────┤
│                                                      │
│  [Drop Zone / File Selection]                      │
│  ┌────────────────────────────────────────────────┐ │
│  │  📁 3 files selected                           │ │
│  │  [Show List ▼]                                 │ │
│  └────────────────────────────────────────────────┘ │
│                                                      │
│  [Configuration]                                     │
│  ┌────────────────────────────────────────────────┐ │
│  │  Model: [Dropdown ▼]                           │ │
│  │  Language: [en ▼]                              │ │
│  │  [Advanced Options ▼]                          │ │
│  └────────────────────────────────────────────────┘ │
│                                                      │
│  [Start Transcription Button]                       │
│                                                      │
│  [Progress Bar] (when processing)                   │
│                                                      │
│  [Results Section] (expandable, appears after start)│
│  ┌────────────────────────────────────────────────┐ │
│  │  ✓ 2/3 Complete                                │ │
│  │  [Transcription List]                          │ │
│  │  [Preview/Edit Area]                           │ │
│  │  [Export Options]                              │ │
│  └────────────────────────────────────────────────┘ │
│                                                      │
└─────────────────────────────────────────────────────┘
```

### State Management

**App States**:
1. **Setup**: Files selected, ready to configure
2. **Processing**: Transcription in progress
3. **Complete**: All transcriptions done, ready to review/export
4. **Error**: Something went wrong

**UI Adapts Based on State**:
- Setup: Show configuration prominently
- Processing: Show progress, hide export options
- Complete: Show results, enable export
- Error: Show error, allow retry

## Detailed Component Design

### Model Selector Component

```swift
struct ModelSelector: View {
    @Binding var selectedModel: WhisperModel
    @Binding var customPath: String

    var body: some View {
        VStack(alignment: .leading) {
            Text("Model")
            Picker("", selection: $selectedModel) {
                ForEach(WhisperModel.allCases, id: \.self) { model in
                    Text(model.displayName).tag(model)
                }
            }

            if selectedModel == .custom {
                HStack {
                    TextField("Model path", text: $customPath)
                    Button("Browse...") { /* browse */ }
                }
            }

            if selectedModel != .custom {
                Text(modelInfo)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
```

### Transcription List Component

```swift
struct TranscriptionListView: View {
    @ObservedObject var manager: TranscriptionManager
    @Binding var selectedTranscription: TranscriptionResult?

    var body: some View {
        List {
            ForEach(manager.completedTranscriptions) { transcription in
                TranscriptionRow(
                    transcription: transcription,
                    isSelected: selectedTranscription?.id == transcription.id
                )
                .onTapGesture {
                    selectedTranscription = transcription
                }
            }
        }
    }
}
```

### Export Options Component

```swift
struct ExportOptionsView: View {
    @Binding var selectedFormat: ExportFormat
    let onExport: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Text("Export Format")
            Picker("", selection: $selectedFormat) {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }

            Button("Export") {
                onExport()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
```

## User Experience Improvements

### 1. Progressive Disclosure
- Hide advanced options by default
- Show configuration only when needed
- Expand results section after transcription starts

### 2. Feedback & Status
- Clear visual indicators for each file status
- Progress bar with percentage
- Time estimates (if possible)
- Success/error messages inline

### 3. Error Handling
- Show errors per-file, not fail entire batch
- Allow retry for failed files
- Clear error messages with suggestions

### 4. Keyboard Shortcuts
- ⌘O: Open directory
- ⌘R: Start transcription
- ⌘E: Export
- ⌘S: Save (if editing)

### 5. Accessibility
- VoiceOver support
- Keyboard navigation
- High contrast mode support
- Clear labels and descriptions

## Implementation Priority

### Phase 1 (MVP+)
1. ✅ Model selector dropdown
2. ✅ Transcription preview list
3. ✅ Export format selection
4. ✅ Results section that appears after completion

### Phase 2 (Enhanced)
1. Individual file editing
2. Multiple export formats
3. File list with details
4. Better error handling per-file

### Phase 3 (Advanced)
1. Real-time transcription display
2. Search/filter transcriptions
3. Batch editing
4. Export templates

## Conclusion

The recommended approach (Option C) provides:
- ✅ Better UX without overwhelming complexity
- ✅ Progressive disclosure (show what's needed when)
- ✅ Clear workflow (Setup → Process → Review → Export)
- ✅ Flexibility (multiple export formats)
- ✅ Visibility (see results before exporting)

This balances simplicity with functionality, making the app more useful while remaining approachable.

