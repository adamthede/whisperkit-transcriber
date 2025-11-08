//
//  Models.swift
//  WhisperKitTranscriber
//
//  Data models for transcription app
//

import Foundation

enum WhisperModel: String, CaseIterable, Identifiable {
    case auto = "auto"
    case tiny = "tiny"
    case base = "base"
    case small = "small"
    case medium = "medium"
    case largeV3 = "large-v3"
    case custom = "custom"

    var id: String { rawValue }

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

    var info: String {
        switch self {
        case .auto: return "WhisperKit will automatically select the best model"
        case .tiny: return "Fastest transcription, lower accuracy. Good for quick previews."
        case .base: return "Fast transcription with good accuracy. Good balance."
        case .small: return "Balanced speed and accuracy. Recommended for most use cases."
        case .medium: return "High quality transcription. Slower but more accurate."
        case .largeV3: return "Best quality transcription. Requires more time and resources."
        case .custom: return "Use a custom model from your local filesystem"
        }
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case markdown = "md"
    case plainText = "txt"
    case json = "json"
    case individualFiles = "individual"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .markdown: return "Markdown (Combined)"
        case .plainText: return "Plain Text (Combined)"
        case .json: return "JSON (Structured)"
        case .individualFiles: return "Individual Files (One per audio)"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .plainText: return "txt"
        case .json: return "json"
        case .individualFiles: return "md"
        }
    }
}

enum Language: String, CaseIterable, Identifiable {
    case auto = "auto"
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portuguese = "pt"
    case russian = "ru"
    case japanese = "ja"
    case korean = "ko"
    case chinese = "zh"
    case arabic = "ar"
    case dutch = "nl"
    case polish = "pl"
    case turkish = "tr"
    case swedish = "sv"
    case norwegian = "no"
    case danish = "da"
    case finnish = "fi"
    case greek = "el"
    case hindi = "hi"
    case thai = "th"
    case vietnamese = "vi"
    case czech = "cs"
    case hungarian = "hu"
    case romanian = "ro"
    case ukrainian = "uk"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto-detect"
        case .english: return "English"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        case .italian: return "Italian"
        case .portuguese: return "Portuguese"
        case .russian: return "Russian"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .chinese: return "Chinese"
        case .arabic: return "Arabic"
        case .dutch: return "Dutch"
        case .polish: return "Polish"
        case .turkish: return "Turkish"
        case .swedish: return "Swedish"
        case .norwegian: return "Norwegian"
        case .danish: return "Danish"
        case .finnish: return "Finnish"
        case .greek: return "Greek"
        case .hindi: return "Hindi"
        case .thai: return "Thai"
        case .vietnamese: return "Vietnamese"
        case .czech: return "Czech"
        case .hungarian: return "Hungarian"
        case .romanian: return "Romanian"
        case .ukrainian: return "Ukrainian"
        }
    }

    var code: String {
        return rawValue
    }
}

class TranscriptionResult: Identifiable, Hashable {
    let id: UUID
    let sourcePath: String
    let fileName: String
    let text: String
    let duration: Int?
    let createdAt: Date
    let modelUsed: String?
    var editedText: String

    init(id: UUID = UUID(), sourcePath: String, fileName: String, text: String, duration: Int?, createdAt: Date, modelUsed: String? = nil) {
        self.id = id
        self.sourcePath = sourcePath
        self.fileName = fileName
        self.text = text
        self.duration = duration
        self.createdAt = createdAt
        self.modelUsed = modelUsed
        self.editedText = text
    }

    var displayText: String {
        editedText
    }

    var preview: String {
        let preview = displayText.prefix(100)
        return preview.count < displayText.count ? String(preview) + "..." : displayText
    }

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TranscriptionResult, rhs: TranscriptionResult) -> Bool {
        lhs.id == rhs.id
    }
}

struct FileStatus: Identifiable {
    let id: UUID
    let url: URL
    var status: ProcessingStatus
    var transcription: TranscriptionResult?

    enum ProcessingStatus: Equatable {
        case pending
        case processing
        case completed
        case failed(String)

        static func == (lhs: ProcessingStatus, rhs: ProcessingStatus) -> Bool {
            switch (lhs, rhs) {
            case (.pending, .pending),
                 (.processing, .processing),
                 (.completed, .completed):
                return true
            case (.failed(let lhsMsg), .failed(let rhsMsg)):
                return lhsMsg == rhsMsg
            default:
                return false
            }
        }
    }
}

