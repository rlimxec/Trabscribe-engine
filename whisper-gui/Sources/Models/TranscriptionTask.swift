import Foundation

/// Source of media for transcription
enum MediaSource: Equatable {
    case file(url: URL)
    case youtube(url: String)
    case microphone

    var displayName: String {
        switch self {
        case .file(let url):
            return url.lastPathComponent
        case .youtube(let url):
            return Self.shortenYouTubeURL(url)
        case .microphone:
            return "🎤 Запись микрофона"
        }
    }

    var icon: String {
        switch self {
        case .file: return "doc"
        case .youtube: return "video"
        case .microphone: return "mic"
        }
    }

    private static func shortenYouTubeURL(_ url: String) -> String {
        if let idx = url.range(of: "v=") {
            let id = url[idx.upperBound...].prefix(11)
            return "YouTube: \(id)..."
        }
        return url
    }
}

/// Current state of a transcription task
enum TranscriptionState: Equatable {
    case pending
    case downloading(progress: Double)
    case transcribing(progress: Double)
    case completed
    case failed(error: String)

    var isActive: Bool {
        switch self {
        case .pending, .downloading, .transcribing: return true
        case .completed, .failed: return false
        }
    }

    var progressValue: Double {
        switch self {
        case .pending: return 0
        case .downloading(let p): return p
        case .transcribing(let p): return p
        case .completed: return 1
        case .failed: return 0
        }
    }

    var label: String {
        switch self {
        case .pending: return "Ожидание"
        case .downloading(let p): return "Загрузка \(Int(p * 100))%"
        case .transcribing(let p): return "Транскрибация \(Int(p * 100))%"
        case .completed: return "Готово"
        case .failed(let e): return "Ошибка: \(e)"
        }
    }
}

/// Represents a single transcription job
@Observable
final class TranscriptionTask: Identifiable {
    let id: UUID
    let source: MediaSource
    var state: TranscriptionState
    var outputText: String = ""
    var outputFiles: [URL] = []
    let createdAt: Date

    init(source: MediaSource) {
        self.id = UUID()
        self.source = source
        self.state = .pending
        self.createdAt = Date()
    }
}
