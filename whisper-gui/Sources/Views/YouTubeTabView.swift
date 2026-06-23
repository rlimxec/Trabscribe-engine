import SwiftUI

struct YouTubeTabView: View {
    @Environment(AppSettings.self) private var settings

    @State private var urlString = ""
    @State private var isProcessing = false
    @State private var videoInfo: YouTubeVideoInfo?
    @State private var transcriptText = ""
    @State private var outputFiles: [URL] = []
    @State private var phase: Phase = .idle

    enum Phase {
        case idle
        case fetchingInfo
        case downloading(progress: Double)
        case transcribing(progress: Double)
        case completed
        case failed(String)
    }

    private let youtubeService = YouTubeService.shared
    private let transcriptionService = TranscriptionService.shared

    var body: some View {
        VStack(spacing: 16) {
            // URL input
            VStack(alignment: .leading, spacing: 8) {
                Text("Ссылка на YouTube видео")
                    .font(.headline)

                HStack {
                    TextField("https://youtube.com/watch?v=...", text: $urlString)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isProcessing)

                    Button("Вставить") {
                        if let str = NSPasteboard.general.string(forType: .string) {
                            urlString = str
                        }
                    }
                    .disabled(isProcessing)

                    Button(action: processVideo) {
                        Label("Старт", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(urlString.trimmingCharacters(in: .whitespaces).isEmpty || isProcessing)
                }
            }
            .padding(.horizontal)

            // Video info
            if let info = videoInfo {
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.title).font(.headline).lineLimit(2)
                    Text(info.channel).font(.caption).foregroundColor(.secondary)
                    Text(formatDuration(info.duration)).font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.gray.opacity(0.08))
                .cornerRadius(8)
                .padding(.horizontal)
            }

            // Progress
            if isProcessing {
                VStack(spacing: 12) {
                    HStack {
                        Text(phaseLabel).font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(phaseProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    ProgressView(value: phaseProgress)
                        .progressViewStyle(.linear)

                    Button(role: .destructive) {
                        cancelProcessing()
                    } label: {
                        Label("Отмена", systemImage: "xmark.circle")
                    }
                }
                .padding(.horizontal)
            }

            // Error
            if case .failed(let msg) = phase {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding()
                .background(Color.red.opacity(0.06))
                .cornerRadius(8)
                .padding(.horizontal)
            }

            // Result
            if case .completed = phase {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Готово!")
                            .font(.headline)
                        Spacer()
                        Button("Открыть в Finder") {
                            if let file = outputFiles.first {
                                NSWorkspace.shared.activateFileViewerSelecting([file])
                            }
                        }
                        Button("Копировать текст") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(transcriptText, forType: .string)
                        }
                    }

                    ScrollView {
                        Text(transcriptText.isEmpty ? "(текст сохранён в файл)" : transcriptText)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .frame(maxHeight: 200)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                }
                .padding(.horizontal)
            }

            Spacer()
        }
        .padding(.vertical)
    }

    // MARK: - Processing pipeline
    private func processVideo() {
        let url = urlString.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }

        isProcessing = true
        phase = .fetchingInfo
        videoInfo = nil
        transcriptText = ""
        outputFiles = []

        let ys = youtubeService
        let ts = transcriptionService

        Task {
            // 1. Fetch info
            do {
                let info = try await ys.fetchInfo(url: url)
                await MainActor.run { videoInfo = info }
            } catch {
                await MainActor.run {
                    phase = .failed(error.localizedDescription)
                    isProcessing = false
                }
                return
            }

            // 2. Download audio
            await MainActor.run { phase = .downloading(progress: 0) }
            let audioURL: URL
            do {
                audioURL = try await ys.downloadAudio(url: url) { progress in
                    Task { @MainActor in
                        self.phase = .downloading(progress: progress)
                    }
                }
            } catch {
                await MainActor.run {
                    phase = .failed(error.localizedDescription)
                    isProcessing = false
                }
                return
            }

            // 3. Transcribe
            await MainActor.run { phase = .transcribing(progress: 0) }
            do {
                try settings.ensureOutputDir()

                let (text, files) = try await ts.transcribe(
                    inputURL: audioURL,
                    modelPath: settings.modelPath,
                    language: settings.language,
                    outputDir: settings.outputDir,
                    formats: settings.activeFormats,
                    threads: settings.threads,
                    gpuDevice: settings.gpuDevice,
                    onProgress: { progress in
                        Task { @MainActor in
                            self.phase = .transcribing(progress: progress)
                        }
                    }
                )

                await MainActor.run {
                    transcriptText = text
                    outputFiles = files
                    phase = .completed
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    phase = .failed(error.localizedDescription)
                    isProcessing = false
                }
            }

            // Cleanup temp audio
            let tempDir = audioURL.deletingLastPathComponent()
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    private func cancelProcessing() {
        youtubeService.cancel()
        transcriptionService.cancel()
        isProcessing = false
        phase = .idle
    }

    // MARK: - Helpers
    private var phaseLabel: String {
        switch phase {
        case .idle: return ""
        case .fetchingInfo: return "Получение информации..."
        case .downloading: return "Загрузка аудио..."
        case .transcribing: return "Транскрибация..."
        case .completed: return "Готово"
        case .failed: return "Ошибка"
        }
    }

    private var phaseProgress: Double {
        switch phase {
        case .downloading(let p): return p
        case .transcribing(let p): return p
        case .completed: return 1
        default: return 0
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: interval) ?? "0:00"
    }
}
