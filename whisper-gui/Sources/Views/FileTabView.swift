import SwiftUI
import UniformTypeIdentifiers

struct FileTabView: View {
    @Environment(AppSettings.self) private var settings

    @State private var tasks: [TranscriptionTask] = []
    @State private var isProcessing = false
    @State private var isDropTargeted = false

    private let transcriptionService = TranscriptionService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                Button(action: selectFiles) {
                    Label("Выбрать файлы", systemImage: "doc.badge.plus")
                }
                .disabled(isProcessing)

                Button(action: selectFolder) {
                    Label("Выбрать папку", systemImage: "folder.badge.plus")
                }
                .disabled(isProcessing)

                Spacer()

                if !tasks.isEmpty {
                    Button(role: .destructive, action: clearCompleted) {
                        Label("Очистить", systemImage: "trash")
                    }
                    .disabled(isProcessing)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if tasks.isEmpty {
                dropZone
            } else {
                fileList
            }

            Divider()

            bottomBar
        }
    }

    // MARK: - Drop zone
    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundColor(isDropTargeted ? .accentColor : .secondary.opacity(0.4))
                .padding(20)

            VStack(spacing: 12) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("Перетащите аудио или видео файлы сюда")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Text("Поддерживаются любые форматы, которые читает ffmpeg")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .padding()
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    // MARK: - File list
    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(tasks) { task in
                    TaskRowView(task: task)
                        .padding(.horizontal)
                        .contextMenu {
                            if case .completed = task.state {
                                Button("Открыть в Finder") {
                                    if let file = task.outputFiles.first {
                                        NSWorkspace.shared.activateFileViewerSelecting([file])
                                    }
                                }
                                Button("Копировать текст") {
                                    copyToClipboard(task.outputText)
                                }
                            }
                            if !task.state.isActive {
                                Button("Удалить", role: .destructive) {
                                    withAnimation {
                                        tasks.removeAll { $0.id == task.id }
                                    }
                                }
                            }
                        }
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Bottom bar
    private var bottomBar: some View {
        HStack {
            if isProcessing {
                let active = tasks.filter { $0.state.isActive }.count
                Text("Обрабатывается: \(active) из \(tasks.count)")
                    .foregroundColor(.secondary)
            } else {
                let completed = tasks.filter { if case .completed = $0.state { return true }; return false }.count
                Text("Готово: \(completed) / \(tasks.count)")
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isProcessing {
                Button(role: .destructive) {
                    transcriptionService.cancel()
                    isProcessing = false
                    for task in tasks where task.state.isActive {
                        task.state = .failed(error: "Отменено")
                    }
                } label: {
                    Label("Стоп", systemImage: "stop.fill")
                }
            } else if !tasks.isEmpty {
                Button(action: startProcessing) {
                    Label("Старт", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Actions
    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .audio, .movie, .mpeg4Movie, .quickTimeMovie,
            .init(filenameExtension: "mp3")!,
            .init(filenameExtension: "wav")!,
            .init(filenameExtension: "m4a")!,
            .init(filenameExtension: "ogg")!,
            .init(filenameExtension: "flac")!,
            .init(filenameExtension: "aac")!,
            .init(filenameExtension: "wma")!,
            .init(filenameExtension: "aiff")!,
        ].compactMap { $0 }

        guard panel.runModal() == .OK else { return }
        let newTasks = panel.urls.map { TranscriptionTask(source: .file(url: $0)) }
        tasks.append(contentsOf: newTasks)
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true

        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let fm = FileManager.default
        let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
        var urls: [URL] = []

        while let fileURL = enumerator?.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            let audioExts = Set(["mp3", "wav", "m4a", "ogg", "flac", "aac", "wma", "aiff", "opus",
                                 "mp4", "mov", "avi", "mkv", "webm"])
            guard audioExts.contains(ext) else { continue }
            guard let attrs = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  attrs.isRegularFile == true else { continue }
            urls.append(fileURL)
        }

        let newTasks = urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            .map { TranscriptionTask(source: .file(url: $0)) }
        tasks.append(contentsOf: newTasks)
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    let task = TranscriptionTask(source: .file(url: url))
                    self.tasks.append(task)
                }
            }
        }
    }

    private func startProcessing() {
        isProcessing = true
        processNext()
    }

    private func processNext() {
        guard let task = tasks.first(where: { if case .pending = $0.state { return true }; return false }) else {
            isProcessing = false
            return
        }

        task.state = .transcribing(progress: 0)

        guard case .file(let inputURL) = task.source else { return }

        Task {
            do {
                try settings.ensureOutputDir()

                let (text, files) = try await transcriptionService.transcribe(
                    inputURL: inputURL,
                    modelPath: settings.modelPath,
                    language: settings.language,
                    outputDir: settings.outputDir,
                    formats: settings.activeFormats,
                    threads: settings.threads,
                    gpuDevice: settings.gpuDevice,
                    onProgress: { progress in
                        task.state = .transcribing(progress: progress)
                    }
                )

                task.outputText = text
                task.outputFiles = files
                task.state = .completed

                await MainActor.run { processNext() }
            } catch {
                task.state = .failed(error: error.localizedDescription)
                await MainActor.run { processNext() }
            }
        }
    }

    private func clearCompleted() {
        tasks.removeAll { !$0.state.isActive }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Task Row
private struct TaskRowView: View {
    let task: TranscriptionTask

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: task.source.icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.source.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .fontWeight(.medium)

                Text(task.state.label)
                    .font(.caption)
                    .foregroundColor(statusColor)
            }

            Spacer()

            if task.state.isActive {
                ProgressView(value: task.state.progressValue)
                    .frame(width: 80)
            } else if case .completed = task.state {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if case .failed = task.state {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    private var iconColor: Color {
        switch task.state {
        case .completed: return .green
        case .failed: return .red
        case .transcribing, .downloading: return .blue
        case .pending: return .secondary
        }
    }

    private var statusColor: Color {
        switch task.state {
        case .completed: return .green
        case .failed: return .red
        default: return .secondary
        }
    }
}
