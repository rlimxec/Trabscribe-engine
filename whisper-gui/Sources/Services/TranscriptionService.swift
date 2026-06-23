import Foundation

// MARK: - Errors
enum TranscriptionError: LocalizedError {
    case whisperNotFound
    case processFailed(exitCode: Int32, stderr: String)
    case outputFileNotFound(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .whisperNotFound:
            return "whisper-cli не найден. Установите: brew install whisper-cpp"
        case .processFailed(let code, let stderr):
            return "Ошибка (код \(code)): \(stderr.truncated(200))"
        case .outputFileNotFound(let path):
            return "Файл результата не найден: \(path)"
        case .cancelled:
            return "Отменено пользователем"
        }
    }
}

// MARK: - Service
/// Manages whisper-cli process execution
final class TranscriptionService: @unchecked Sendable {
    nonisolated(unsafe) static let shared = TranscriptionService()

    private var currentProcess: Process?
    private let decoder = JSONDecoder()

    private let whisperPath = "/opt/homebrew/bin/whisper-cli"

    // MARK: - Transcribe
    /// Run whisper-cli on a media file. Returns transcribed text and list of output files.
    /// Progress is reported via the `onProgress` callback (0.0 ... 1.0).
    func transcribe(
        inputURL: URL,
        modelPath: String,
        language: String,
        outputDir: String,
        formats: Set<String>,
        threads: Int,
        gpuDevice: Int,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> (text: String, files: [URL]) {
        // Guard: whisper-cli exists
        guard FileManager.default.isExecutableFile(atPath: whisperPath) else {
            throw TranscriptionError.whisperNotFound
        }

        // Ensure output directory
        let outDirURL = URL(fileURLWithPath: outputDir)
        try FileManager.default.createDirectory(at: outDirURL, withIntermediateDirectories: true)

        // Build command arguments
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let outputBase = outDirURL.appendingPathComponent(baseName).path

        var args: [String] = [
            "-m", modelPath,
            "-f", inputURL.path,
            "-t", String(threads),
            "-dev", String(gpuDevice),
            "-pp",
            "--no-prints",
            "-of", outputBase,
        ]

        if language != "auto" {
            args += ["-l", language]
        }

        for fmt in formats {
            args += ["-o\(fmt)"]
        }

        // Fallback to txt if no format selected
        if formats.isEmpty {
            args += ["-otxt"]
        }

        return try await runProcess(args: args, outputBase: outputBase, formats: formats, onProgress: onProgress)
    }

    // MARK: - Process runner
    private func runProcess(
        args: [String],
        outputBase: String,
        formats: Set<String>,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> (text: String, files: [URL]) {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: self.whisperPath)
            process.arguments = args
            self.currentProcess = process

            // Stderr pipe — progress is printed to stderr
            let errPipe = Pipe()
            process.standardError = errPipe
            // Not reading stdout since we use --no-prints + output files

            // Buffer for stderr (collects progress + final info)
            let errBuffer = LockedBuffer()

            errPipe.fileHandleForReading.readabilityHandler = { [onProgress] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let chunk = String(data: data, encoding: .utf8) {
                    errBuffer.append(chunk)
                    if chunk.contains("progress") {
                        let pattern = /progress\s*=\s*(\d+)/
                        for match in chunk.matches(of: pattern) {
                            if let pct = Double(match.1) {
                                let progress = min(max(pct / 100.0, 0), 1)
                                Task { @MainActor in onProgress(progress) }
                            }
                        }
                    }
                }
            }

            process.terminationHandler = { [self, onProgress] proc in
                errPipe.fileHandleForReading.readabilityHandler = nil

                let remaining = errPipe.fileHandleForReading.readDataToEndOfFile()
                if let chunk = String(data: remaining, encoding: .utf8), !chunk.isEmpty {
                    errBuffer.append(chunk)
                    if chunk.contains("progress") {
                        let pattern = /progress\s*=\s*(\d+)/
                        for match in chunk.matches(of: pattern) {
                            if let pct = Double(match.1) {
                                let progress = min(max(pct / 100.0, 0), 1)
                                Task { @MainActor in onProgress(progress) }
                            }
                        }
                    }
                }

                guard proc.terminationStatus == 0 else {
                    let stderr = errBuffer.content
                    continuation.resume(throwing: TranscriptionError.processFailed(
                        exitCode: proc.terminationStatus,
                        stderr: stderr
                    ))
                    return
                }

                // Read output files
                let fm = FileManager.default
                var text = ""
                var outputFiles: [URL] = []

                // Try reading output files
                let allFormats = formats.isEmpty ? ["txt"] : formats
                for fmt in allFormats {
                    let path = outputBase + "." + fmt
                    let url = URL(fileURLWithPath: path)
                    guard fm.fileExists(atPath: path) else { continue }

                    outputFiles.append(url)

                    if fmt == "txt", let data = fm.contents(atPath: path) {
                        text = String(data: data, encoding: .utf8) ?? ""
                    }
                }

                if outputFiles.isEmpty {
                    // Fallback: try to extract from stderr lines with timestamps
                    let full = errBuffer.content
                    var fallbackLines: [String] = []
                    for line in full.components(separatedBy: .newlines) where line.contains("-->") {
                        if let textPart = line.split(separator: "]").last?.trimmingCharacters(in: .whitespaces) {
                            let cleaned = textPart
                                .replacingOccurrences(of: #"^\s*\[?\]?"#, with: "", options: .regularExpression)
                                .trimmingCharacters(in: .whitespaces)
                            if !cleaned.isEmpty { fallbackLines.append(cleaned) }
                        }
                    }
                    text = fallbackLines.joined(separator: "\n")
                    if !text.isEmpty {
                        continuation.resume(returning: (text, []))
                        return
                    }
                    continuation.resume(throwing: TranscriptionError.outputFileNotFound(outputBase + ".txt"))
                    return
                }

                continuation.resume(returning: (text, outputFiles))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: TranscriptionError.processFailed(exitCode: -1, stderr: error.localizedDescription))
            }
        }
    }

    // MARK: - Cancel
    func cancel() {
        currentProcess?.terminate()
        currentProcess = nil
    }

}

// MARK: - Helpers

/// Thread-safe string buffer
final class LockedBuffer: @unchecked Sendable {
    private var storage = ""
    private let lock = NSLock()

    var content: String {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func append(_ string: String) {
        lock.lock(); defer { lock.unlock() }
        storage += string
    }
}

extension String {
    func truncated(_ max: Int) -> String {
        count > max ? String(prefix(max)) + "…" : self
    }
}
