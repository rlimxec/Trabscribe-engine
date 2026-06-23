import Foundation

// MARK: - Errors
enum YouTubeError: LocalizedError {
    case ytDlpNotFound
    case downloadFailed(stderr: String)
    case invalidURL
    case cancelled

    var errorDescription: String? {
        switch self {
        case .ytDlpNotFound:
            return "yt-dlp не найден. Установите: brew install yt-dlp"
        case .downloadFailed(let err):
            return "Ошибка загрузки: \(err.truncated(300))"
        case .invalidURL:
            return "Некорректный URL YouTube"
        case .cancelled:
            return "Загрузка отменена"
        }
    }
}

/// Video metadata from yt-dlp
struct YouTubeVideoInfo: Sendable {
    let title: String
    let channel: String
    let duration: TimeInterval
    let webpageURL: String
}

// MARK: - Service
/// Downloads audio from YouTube via yt-dlp
final class YouTubeService: @unchecked Sendable {
    nonisolated(unsafe) static let shared = YouTubeService()

    private let ytDlpPath = "/opt/homebrew/bin/yt-dlp"

    private var currentProcess: Process?

    // MARK: - Fetch video info
    /// Fetch video metadata without downloading
    func fetchInfo(url: String) async throws -> YouTubeVideoInfo {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytDlpPath)
        process.arguments = [
            "--dump-json",
            "--no-download",
            url,
        ]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

                guard proc.terminationStatus == 0 else {
                    let err = String(data: errData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: YouTubeError.downloadFailed(stderr: err))
                    return
                }

                do {
                    let json = try JSONSerialization.jsonObject(with: outData) as? [String: Any]
                    let title = json?["title"] as? String ?? "Unknown"
                    let channel = json?["channel"] as? String ?? "Unknown"
                    let duration = json?["duration"] as? TimeInterval ?? 0
                    let webpageURL = json?["webpage_url"] as? String ?? url

                    continuation.resume(returning: YouTubeVideoInfo(
                        title: title,
                        channel: channel,
                        duration: duration,
                        webpageURL: webpageURL
                    ))
                } catch {
                    continuation.resume(throwing: YouTubeError.downloadFailed(stderr: "JSON parse error: \(error.localizedDescription)"))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: YouTubeError.downloadFailed(stderr: error.localizedDescription))
            }
        }
    }

    // MARK: - Download audio
    /// Download audio from YouTube to a temp file. Returns the URL of the downloaded file.
    func downloadAudio(
        url: String,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        // Create temp directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper-gui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // We download as best audio, then convert to wav with ffmpeg
        // Using yt-dlp to get best audio and save to temp dir
        let outputTemplate = tempDir.appendingPathComponent("%(title)s.%(ext)s").path

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytDlpPath)
        process.arguments = [
            "-x",                          // extract audio
            "--audio-format", "wav",       // convert to wav
            "--audio-quality", "0",        // best quality
            "-o", outputTemplate,
            "--no-playlist",
            "--print", "filename",         // print final filename
            url,
        ]

        currentProcess = process

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // Progress buffer
        let errBuffer = LockedBuffer()

        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let chunk = String(data: data, encoding: .utf8) {
                errBuffer.append(chunk)
                // yt-dlp progress: [download]  45.2% of ...
                if chunk.contains("%") {
                    let pattern = /(\d+\.?\d*)\s*%/
                    for match in chunk.matches(of: pattern) {
                        if let pct = Double(match.1) {
                            let progress = min(max(pct / 100.0, 0), 1)
                            DispatchQueue.main.async { onProgress(progress) }
                        }
                    }
                }
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                errPipe.fileHandleForReading.readabilityHandler = nil
                let remaining = errPipe.fileHandleForReading.readDataToEndOfFile()
                if let chunk = String(data: remaining, encoding: .utf8), !chunk.isEmpty {
                    errBuffer.append(chunk)
                    if chunk.contains("%") {
                        let pattern = /(\d+\.?\d*)\s*%/
                        for match in chunk.matches(of: pattern) {
                            if let pct = Double(match.1) {
                                let progress = min(max(pct / 100.0, 0), 1)
                                DispatchQueue.main.async { onProgress(progress) }
                            }
                        }
                    }
                }

                guard proc.terminationStatus == 0 else {
                    let err = errBuffer.content
                    // Clean up temp dir
                    try? FileManager.default.removeItem(at: tempDir)
                    continuation.resume(throwing: YouTubeError.downloadFailed(stderr: err))
                    return
                }

                // Read the filename from stdout (printed by --print filename)
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let outStr = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                // Find the downloaded wav file
                let fm = FileManager.default
                if !outStr.isEmpty, fm.fileExists(atPath: outStr) {
                    continuation.resume(returning: URL(fileURLWithPath: outStr))
                    return
                }

                // Fallback: search temp dir for .wav
                if let files = try? fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil),
                   let wavFile = files.first(where: { $0.pathExtension == "wav" }) {
                    continuation.resume(returning: wavFile)
                    return
                }

                // Last resort: any audio file
                if let files = try? fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil),
                   let audioFile = files.first(where: { ["mp3", "m4a", "opus", "aac", "flac"].contains($0.pathExtension) }) {
                    continuation.resume(returning: audioFile)
                    return
                }

                continuation.resume(throwing: YouTubeError.downloadFailed(stderr: "Файл не найден после загрузки"))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: YouTubeError.downloadFailed(stderr: error.localizedDescription))
            }
        }
    }

    // MARK: - Cancel
    func cancel() {
        currentProcess?.terminate()
        currentProcess = nil
    }

}
