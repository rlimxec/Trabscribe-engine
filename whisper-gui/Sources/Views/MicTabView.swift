import SwiftUI
import AVFoundation

struct MicTabView: View {
    @Environment(AppSettings.self) private var settings

    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var hasPermission = false
    @State private var transcriptText = ""
    @State private var outputFiles: [URL] = []
    @State private var errorMessage: String?
    @State private var recordingDuration: TimeInterval = 0
    @State private var powerLevel: Float = 0
    @State private var timer: Timer?
    @State private var recordedFileURL: URL?

    private let recordingService = RecordingService.shared
    private let transcriptionService = TranscriptionService.shared

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            if !hasPermission {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "mic.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.red)
                    Text("Нет доступа к микрофону")
                        .font(.title3)
                    Button("Разрешить доступ") {
                        Task { @MainActor in
                            hasPermission = await recordingService.requestPermission()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
                Spacer()
            }

            // Recording visualization
            ZStack {
                Circle()
                    .stroke(lineWidth: 4)
                    .foregroundColor(isRecording ? .red.opacity(0.3) : .gray.opacity(0.2))
                    .frame(width: 160, height: 160)

                Circle()
                    .trim(from: 0, to: isRecording ? 1 : 0)
                    .stroke(style: StrokeStyle(lineWidth: 4, dash: [2]))
                    .foregroundColor(.red)
                    .frame(width: 160, height: 160)
                    .opacity(isRecording ? 0.5 : 0)

                if isRecording {
                    Circle()
                        .fill(Color.red.opacity(0.1 + Double(powerLevel) * 0.5))
                        .frame(width: 120, height: 120)
                        .animation(.easeInOut(duration: 0.1), value: powerLevel)
                }

                Image(systemName: isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 48))
                    .foregroundColor(isRecording ? .red : .primary)
            }

            Text(formatTime(recordingDuration))
                .font(.title.monospacedDigit())
                .foregroundColor(isRecording ? .red : .secondary)

            Button(action: toggleRecording) {
                Label(
                    isRecording ? "Остановить запись" : "Начать запись",
                    systemImage: isRecording ? "stop.fill" : "record.circle"
                )
                .font(.title2)
            }
            .buttonStyle(.borderedProminent)
            .tint(isRecording ? .red : .accentColor)
            .disabled(isTranscribing)

            if recordedFileURL != nil && !isRecording && !isTranscribing {
                Button(action: transcribeRecording) {
                    Label("Транскрибировать запись", systemImage: "text.quote")
                }
                .buttonStyle(.borderedProminent)
            }

            if isTranscribing {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Транскрибация...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding()
                    .background(Color.red.opacity(0.06))
                    .cornerRadius(8)
            }

            if !transcriptText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Результат")
                            .font(.headline)
                        Spacer()
                        Button("Копировать") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(transcriptText, forType: .string)
                        }
                    }
                    ScrollView {
                        Text(transcriptText)
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
        .onAppear {
            hasPermission = recordingService.hasPermission
        }
        .onDisappear {
            timer?.invalidate()
            if isRecording {
                _ = recordingService.stopRecording()
            }
        }
    }

    // MARK: - Actions
    private func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        do {
            try recordingService.startRecording()
            isRecording = true
            transcriptText = ""
            errorMessage = nil

            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                recordingDuration = recordingService.currentTime
                powerLevel = recordingService.averagePower
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopRecording() {
        timer?.invalidate()
        timer = nil
        recordedFileURL = recordingService.stopRecording()
        isRecording = false
    }

    private func transcribeRecording() {
        guard let url = recordedFileURL else { return }
        isTranscribing = true
        errorMessage = nil

        Task {
            do {
                try settings.ensureOutputDir()

                let (text, files) = try await transcriptionService.transcribe(
                    inputURL: url,
                    modelPath: settings.modelPath,
                    language: settings.language,
                    outputDir: settings.outputDir,
                    formats: settings.activeFormats,
                    threads: settings.threads,
                    gpuDevice: settings.gpuDevice,
                    onProgress: { _ in }
                )

                await MainActor.run {
                    transcriptText = text
                    outputFiles = files
                    isTranscribing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isTranscribing = false
                }
            }
        }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(interval) / 60, Int(interval) % 60)
    }
}
