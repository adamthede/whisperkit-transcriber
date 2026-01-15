# Implementation Plan: Multiple Export Formats

## Overview
Add support for exporting transcriptions in multiple formats: SRT, VTT, TXT, JSON (already exists), DOCX, PDF, and HTML. This will significantly expand the use cases for the application, especially for video subtitles and document generation.

## Current State
- **Existing formats**: Markdown, Plain Text, JSON, Individual Files
- **Export location**: `TranscriptionManager.swift` - `exportTranscriptions()` method
- **Format enum**: `ExportFormat` in `Models.swift`
- **Current limitation**: No timestamp/segment data available for SRT/VTT formats

## Technical Approach

### Phase 1: Add Format Definitions
1. Extend `ExportFormat` enum in `Models.swift` to include new formats
2. Add file extension mappings
3. Add display names for UI

### Phase 2: Implement Format Exporters
Create separate exporter methods for each format:
- `exportSRT()` - SubRip subtitle format
- `exportVTT()` - WebVTT subtitle format
- `exportHTML()` - HTML document format
- `exportDOCX()` - Microsoft Word format (requires library)
- `exportPDF()` - PDF document format (requires AppKit)

### Phase 3: Handle Timestamp Requirements
- **Challenge**: SRT/VTT require timestamps, but current transcription only provides full text
- **Solution Options**:
  1. **Option A (Preferred)**: Modify WhisperKit CLI call to request timestamped output
     - Check if `whisperkit-cli` supports `--output-format json` or `--with-timestamps`
     - Parse JSON output with segment timestamps
  2. **Option B (Fallback)**: Estimate timestamps based on text length and duration
     - Divide text into sentences/segments
     - Distribute duration proportionally
  3. **Option C (Future)**: Use WhisperKit API directly instead of CLI for better control

### Phase 4: Update UI
- Add new format options to export picker in `ContentView.swift`
- Update file extension handling in save dialog

## Implementation Steps

### Step 1: Update Models.swift

**File**: `WhisperKit Transcriber/WhisperKit Transcriber/Models.swift`

**Changes**:
1. Extend `ExportFormat` enum:
```swift
enum ExportFormat: String, CaseIterable, Identifiable {
    case markdown = "md"
    case plainText = "txt"
    case json = "json"
    case srt = "srt"
    case vtt = "vtt"
    case html = "html"
    case docx = "docx"
    case pdf = "pdf"
    case individualFiles = "individual"

    // ... existing code ...

    var displayName: String {
        switch self {
        case .markdown: return "Markdown (Combined)"
        case .plainText: return "Plain Text (Combined)"
        case .json: return "JSON (Structured)"
        case .srt: return "SRT Subtitles"
        case .vtt: return "WebVTT Subtitles"
        case .html: return "HTML Document"
        case .docx: return "Microsoft Word (.docx)"
        case .pdf: return "PDF Document"
        case .individualFiles: return "Individual Files (One per audio)"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .plainText: return "txt"
        case .json: return "json"
        case .srt: return "srt"
        case .vtt: return "vtt"
        case .html: return "html"
        case .docx: return "docx"
        case .pdf: return "pdf"
        case .individualFiles: return "md"
        }
    }
}
```

### Step 2: Create Timestamp Data Structure

**File**: `WhisperKit Transcriber/WhisperKit Transcriber/Models.swift`

**Add new struct**:
```swift
struct TranscriptionSegment: Identifiable {
    let id: UUID
    let startTime: Double  // seconds
    let endTime: Double    // seconds
    let text: String
    let speaker: String?   // For future diarization support
}

extension TranscriptionResult {
    var segments: [TranscriptionSegment] {
        // For now, estimate segments from text
        // TODO: Parse from WhisperKit JSON output if available
        return estimateSegments(from: displayText, duration: duration)
    }

    private func estimateSegments(from text: String, duration: Int?) -> [TranscriptionSegment] {
        guard let duration = duration else {
            // No duration, return single segment
            return [TranscriptionSegment(
                id: UUID(),
                startTime: 0,
                endTime: Double(duration ?? 0),
                text: text
            )]
        }

        // Split text into sentences
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !sentences.isEmpty else {
            return [TranscriptionSegment(id: UUID(), startTime: 0, endTime: Double(duration), text: text)]
        }

        // Estimate time per character
        let totalChars = text.count
        let timePerChar = Double(duration) / Double(max(totalChars, 1))

        var segments: [TranscriptionSegment] = []
        var currentTime: Double = 0

        for (index, sentence) in sentences.enumerated() {
            let sentenceDuration = Double(sentence.count) * timePerChar
            let endTime = min(currentTime + sentenceDuration, Double(duration))

            segments.append(TranscriptionSegment(
                id: UUID(),
                startTime: currentTime,
                endTime: endTime,
                text: sentence
            ))

            currentTime = endTime
        }

        return segments
    }
}
```

### Step 3: Modify TranscriptionManager to Capture Timestamps

**File**: `WhisperKit Transcriber/WhisperKit Transcriber/TranscriptionManager.swift`

**Changes**:
1. Update `transcribeFile()` to check for JSON output option:
```swift
private func transcribeFile(_ audioFile: URL, modelPath: String?) async throws -> TranscriptionResult {
    // ... existing code ...

    // Try to get JSON output with timestamps if available
    let useJSONOutput = true  // Make this configurable later
    var arguments: [String] = [
        "transcribe",
        "--audio-path", audioFile.path,
        "--language", selectedLanguage.code
    ]

    if useJSONOutput {
        // Check if whisperkit-cli supports JSON output
        arguments.append("--output-format")
        arguments.append("json")
    }

    // ... rest of existing code ...

    // Parse output differently if JSON
    if useJSONOutput {
        return try parseJSONTranscription(output: output, audioFile: audioFile, modelPath: modelPath)
    } else {
        return try parseTextTranscription(output: output, audioFile: audioFile, modelPath: modelPath)
    }
}

private func parseJSONTranscription(output: String, audioFile: URL, modelPath: String?) throws -> TranscriptionResult {
    // Parse JSON output with segments
    // Extract segments array with timestamps
    // Store segments in TranscriptionResult (will need to extend model)
}
```

### Step 4: Implement SRT Exporter

**File**: `WhisperKit Transcriber/WhisperKit Transcriber/TranscriptionManager.swift`

**Add method**:
```swift
private func exportSRT(transcriptions: [TranscriptionResult], outputPath: String) throws {
    var srtContent = ""
    var subtitleIndex = 1

    for transcription in transcriptions {
        let segments = transcription.segments

        for segment in segments {
            // SRT format: index, timestamps, text
            srtContent += "\(subtitleIndex)\n"
            srtContent += "\(formatSRTTime(segment.startTime)) --> \(formatSRTTime(segment.endTime))\n"
            srtContent += "\(segment.text)\n\n"
            subtitleIndex += 1
        }
    }

    try srtContent.write(toFile: outputPath, atomically: true, encoding: .utf8)
}

private func formatSRTTime(_ seconds: Double) -> String {
    let hours = Int(seconds) / 3600
    let minutes = (Int(seconds) % 3600) / 60
    let secs = Int(seconds) % 60
    let milliseconds = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)

    return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, milliseconds)
}
```

### Step 5: Implement VTT Exporter

**File**: `WhisperKit Transcriber/WhisperKit Transcriber/TranscriptionManager.swift`

**Add method**:
```swift
private func exportVTT(transcriptions: [TranscriptionResult], outputPath: String) throws {
    var vttContent = "WEBVTT\n\n"

    for transcription in transcriptions {
        // Add file identifier as cue
        vttContent += "NOTE \(transcription.fileName)\n\n"

        let segments = transcription.segments

        for segment in segments {
            vttContent += "\(formatVTTTime(segment.startTime)) --> \(formatVTTTime(segment.endTime))\n"
            vttContent += "\(segment.text)\n\n"
        }
    }

    try vttContent.write(toFile: outputPath, atomically: true, encoding: .utf8)
}

private func formatVTTTime(_ seconds: Double) -> String {
    let hours = Int(seconds) / 3600
    let minutes = (Int(seconds) % 3600) / 60
    let secs = Int(seconds) % 60
    let milliseconds = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)

    return String(format: "%02d:%02d:%06.3f", hours * 3600 + minutes * 60 + secs, Double(milliseconds) / 1000.0)
}
```

### Step 6: Implement HTML Exporter

**File**: `WhisperKit Transcriber/WhisperKit Transcriber/TranscriptionManager.swift`

**Add method**:
```swift
private func exportHTML(transcriptions: [TranscriptionResult], outputPath: String) throws {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    var html = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Audio Transcription</title>
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; max-width: 800px; margin: 40px auto; padding: 20px; }
            h1 { color: #333; border-bottom: 2px solid #333; padding-bottom: 10px; }
            h2 { color: #666; margin-top: 30px; }
            .metadata { color: #888; font-size: 0.9em; margin-bottom: 20px; }
            .transcription { line-height: 1.6; margin-bottom: 30px; }
            .separator { border-top: 1px solid #ddd; margin: 30px 0; }
        </style>
    </head>
    <body>
        <h1>Combined Audio Transcription</h1>
        <div class="metadata">
            <p>Generated: \(formatter.string(from: Date()))</p>
            <p>Files: \(transcriptions.count)</p>
        </div>
    """

    for transcription in transcriptions {
        let fileName = (transcription.fileName as NSString).deletingPathExtension
        html += "<div class=\"transcription\">\n"
        html += "<h2>\(fileName)</h2>\n"

        if let duration = transcription.duration {
            html += "<div class=\"metadata\">Duration: \(TranscriptionManager.formatDuration(duration))</div>\n"
        }

        // Escape HTML entities
        let escapedText = transcription.displayText
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")

        html += "<p>\(escapedText)</p>\n"
        html += "</div>\n"
        html += "<div class=\"separator\"></div>\n"
    }

    html += """
    </body>
    </html>
    """

    try html.write(toFile: outputPath, atomically: true, encoding: .utf8)
}
```

### Step 7: Implement DOCX Exporter (Requires Library)

**File**: `WhisperKit Transcriber/WhisperKit Transcriber/TranscriptionManager.swift`

**Note**: DOCX requires a library. Options:
- **Option A**: Use `ZIPFoundation` + manual XML generation (complex)
- **Option B**: Use `DocX` Swift package (if available)
- **Option C**: Use Python script via Process (fallback)

**Recommended approach**: Start with Option C (Python script) for simplicity:

```swift
private func exportDOCX(transcriptions: [TranscriptionResult], outputPath: String) throws {
    // Create temporary JSON file
    let tempJSON = NSTemporaryDirectory() + UUID().uuidString + ".json"
    try exportJSON(transcriptions: transcriptions, outputPath: tempJSON)

    // Use Python script to convert JSON to DOCX
    let pythonScript = """
    import json
    from docx import Document
    from docx.shared import Inches

    with open('\(tempJSON)', 'r') as f:
        data = json.load(f)

    doc = Document()
    doc.add_heading('Combined Audio Transcription', 0)

    for trans in data['transcriptions']:
        doc.add_heading(trans['file_name'], level=1)
        if trans.get('duration_seconds'):
            doc.add_paragraph(f"Duration: {trans['duration_seconds']} seconds")
        doc.add_paragraph(trans['text'])
        doc.add_page_break()

    doc.save('\(outputPath)')
    """

    // Execute Python script
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = ["-c", pythonScript]
    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        throw TranscriptionError.exportFailed("DOCX export failed")
    }

    // Clean up temp file
    try? FileManager.default.removeItem(atPath: tempJSON)
}
```

**Alternative**: If Python/docx not available, fall back to RTF format (simpler, no dependencies).

### Step 8: Implement PDF Exporter

**File**: `WhisperKit Transcriber/WhisperKit Transcriber/TranscriptionManager.swift`

**Add method** (using AppKit PDF APIs):
```swift
import AppKit

private func exportPDF(transcriptions: [TranscriptionResult], outputPath: String) throws {
    let pdfMetaData = [
        kCGPDFContextCreator: "WhisperKit Transcriber",
        kCGPDFContextTitle: "Audio Transcription"
    ]

    let format = UIGraphicsPDFRendererFormat()
    format.documentInfo = pdfMetaData as [String: Any]

    let pageWidth = 8.5 * 72.0  // 8.5 inches
    let pageHeight = 11.0 * 72.0  // 11 inches
    let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

    let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

    let data = renderer.pdfData { context in
        var yPosition: CGFloat = 50
        let margin: CGFloat = 50
        let lineHeight: CGFloat = 20

        for transcription in transcriptions {
            // Check if we need a new page
            if yPosition > pageHeight - 100 {
                context.beginPage()
                yPosition = 50
            }

            let fileName = (transcription.fileName as NSString).deletingPathExtension
            let titleRect = CGRect(x: margin, y: yPosition, width: pageWidth - 2*margin, height: 30)
            fileName.draw(in: titleRect, withAttributes: [
                .font: NSFont.boldSystemFont(ofSize: 16)
            ])
            yPosition += 35

            if let duration = transcription.duration {
                let durationText = "Duration: \(TranscriptionManager.formatDuration(duration))"
                let durationRect = CGRect(x: margin, y: yPosition, width: pageWidth - 2*margin, height: lineHeight)
                durationText.draw(in: durationRect, withAttributes: [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: NSColor.gray
                ])
                yPosition += lineHeight + 10
            }

            // Split text into lines that fit page width
            let text = transcription.displayText
            let lines = text.components(separatedBy: .newlines)

            for line in lines {
                if yPosition > pageHeight - 50 {
                    context.beginPage()
                    yPosition = 50
                }

                let textRect = CGRect(x: margin, y: yPosition, width: pageWidth - 2*margin, height: lineHeight)
                line.draw(in: textRect, withAttributes: [
                    .font: NSFont.systemFont(ofSize: 12)
                ])
                yPosition += lineHeight
            }

            yPosition += 20  // Space between transcriptions
        }
    }

    try data.write(to: URL(fileURLWithPath: outputPath))
}
```

**Note**: The above uses UIKit-style APIs. For macOS, use `NSPrintOperation` or `NSView` PDF generation instead.

### Step 9: Update Export Switch Statement

**File**: `WhisperKit Transcriber/WhisperKit Transcriber/TranscriptionManager.swift`

**Modify `exportTranscriptions()` method**:
```swift
func exportTranscriptions(format: ExportFormat, outputPath: String, includeTimestamp: Bool = true, alsoExportIndividual: Bool = false) throws {
    let transcriptions = completedTranscriptions

    let finalOutputPath = includeTimestamp && format != .individualFiles ? addTimestampToFilename(outputPath, format: format) : outputPath

    switch format {
    case .markdown:
        try exportMarkdown(transcriptions: transcriptions, outputPath: finalOutputPath)
    case .plainText:
        try exportPlainText(transcriptions: transcriptions, outputPath: finalOutputPath)
    case .json:
        try exportJSON(transcriptions: transcriptions, outputPath: finalOutputPath)
    case .srt:
        try exportSRT(transcriptions: transcriptions, outputPath: finalOutputPath)
    case .vtt:
        try exportVTT(transcriptions: transcriptions, outputPath: finalOutputPath)
    case .html:
        try exportHTML(transcriptions: transcriptions, outputPath: finalOutputPath)
    case .docx:
        try exportDOCX(transcriptions: transcriptions, outputPath: finalOutputPath)
    case .pdf:
        try exportPDF(transcriptions: transcriptions, outputPath: finalOutputPath)
    case .individualFiles:
        try exportIndividualFiles(transcriptions: transcriptions, outputDir: outputPath, includeTimestamp: includeTimestamp)
    }

    // ... rest of existing code ...
}
```

### Step 10: Update ContentView Export Picker

**File**: `WhisperKit Transcriber/WhisperKit Transcriber/ContentView.swift`

**Update export format picker** (should already work if enum is updated, but verify):
```swift
Picker("Export Format", selection: $exportFormat) {
    ForEach(ExportFormat.allCases.filter { $0 != .individualFiles }) { format in
        Text(format.displayName).tag(format)
    }
}
```

## Testing Plan

### Unit Tests
1. **SRT Format**:
   - Test timestamp formatting (hours, minutes, seconds, milliseconds)
   - Test multi-file export
   - Test empty transcriptions
   - Test very long transcriptions

2. **VTT Format**:
   - Test WebVTT header
   - Test timestamp formatting
   - Test file separators

3. **HTML Format**:
   - Test HTML escaping (special characters)
   - Test CSS styling
   - Test multi-file structure

4. **PDF Format**:
   - Test page breaks
   - Test text wrapping
   - Test long documents

5. **DOCX Format**:
   - Test Python script execution
   - Test error handling if Python/docx not available

### Integration Tests
1. Export each format with sample transcriptions
2. Verify files are created correctly
3. Verify file extensions match format
4. Test timestamp inclusion in filenames

### Manual Testing Checklist
- [ ] Export to SRT, verify opens in VLC/media player
- [ ] Export to VTT, verify opens in browser
- [ ] Export to HTML, verify renders correctly
- [ ] Export to PDF, verify opens in Preview
- [ ] Export to DOCX, verify opens in Word/Pages
- [ ] Test with single file
- [ ] Test with multiple files
- [ ] Test with files that have no duration
- [ ] Test timestamp prepending in filename

## Edge Cases to Handle

1. **No duration available**: Use estimated duration or skip timestamps
2. **Empty transcriptions**: Handle gracefully, skip or add placeholder
3. **Very long text**: Ensure PDF/HTML don't break page layout
4. **Special characters**: Properly escape in HTML, handle in PDF
5. **Missing Python/docx**: Fallback to RTF or show error message
6. **File write permissions**: Handle errors gracefully

## Dependencies

### Required
- None (all formats use Foundation/AppKit)

### Optional
- Python 3 + `python-docx` package (for DOCX export)
  - Can be installed via: `pip3 install python-docx`
  - Check availability before attempting DOCX export

## Future Enhancements

1. **Better timestamp extraction**: Parse WhisperKit JSON output directly
2. **Speaker labels in SRT/VTT**: When diarization is implemented
3. **Custom styling**: Allow users to customize HTML/CSS
4. **Batch export**: Export all formats at once
5. **Preview**: Show format preview before exporting

## Estimated Time

- **Phase 1** (Format definitions): 30 minutes
- **Phase 2** (SRT/VTT/HTML): 4-6 hours
- **Phase 3** (PDF): 3-4 hours
- **Phase 4** (DOCX): 2-3 hours
- **Phase 5** (Testing): 2-3 hours
- **Total**: ~12-16 hours

## Notes

- SRT/VTT timestamps are estimated if WhisperKit doesn't provide segment data
- DOCX requires Python + python-docx (consider making this optional)
- PDF generation on macOS may need AppKit-specific APIs (not UIKit)
- Consider making timestamp estimation configurable (sentence-based vs word-based)

