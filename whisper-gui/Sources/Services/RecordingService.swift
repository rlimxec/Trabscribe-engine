import Foundation
import AVFoundation

// MARK: - Errors
enum RecordingError: LocalizedError {
    case noMicrophonePermission
    case recordingFailed(String)
    case noAudioData

    var errorDescription: String? {
        switch self {
        case .noMicrophonePermission:
            return "Нет доступа к микрофону. Разрешите доступ в System Settings."
        case .recordingFailed(let msg):
            return "Ошибка записи: \(msg)"
        case .noAudioData:
            return "Не удалось записать аудио"
        }
    }
}

// MARK: - Service
/// Records audio from the system microphone using AVFoundation
final class RecordingService: NSObject, @unchecked Sendable {
    nonisolated(unsafe) static let shared = RecordingService()

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var completionHandler: ((Result<URL, Error>) -> Void)?

    // MARK: - Permission
    var hasPermission: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    // MARK: - Recording
    /// Start recording to a temporary file
    /// - Returns: true if recording started successfully
    func startRecording() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("recording-\(UUID().uuidString).wav")
        recordingURL = fileURL

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
        audioRecorder?.delegate = self
        audioRecorder?.isMeteringEnabled = true

        guard audioRecorder?.record() == true else {
            throw RecordingError.recordingFailed("Не удалось начать запись")
        }
    }

    /// Stop recording and return the recorded file URL
    func stopRecording() -> URL? {
        audioRecorder?.stop()
        let url = recordingURL
        recordingURL = nil
        audioRecorder = nil
        return url
    }

    /// Current recording duration
    var currentTime: TimeInterval {
        audioRecorder?.currentTime ?? 0
    }

    /// Whether recording is in progress
    var isRecording: Bool {
        audioRecorder?.isRecording ?? false
    }

    /// Current power level (0-1) for visualization
    var averagePower: Float {
        guard audioRecorder?.isRecording == true else { return 0 }
        audioRecorder?.updateMeters()
        let power = audioRecorder?.averagePower(forChannel: 0) ?? -160
        // Convert dB to 0-1 range
        return max(0, (power + 160) / 160)
    }
}

// MARK: - AVAudioRecorderDelegate
extension RecordingService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            completionHandler?(.failure(RecordingError.recordingFailed("Запись прервана")))
            completionHandler = nil
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error {
            completionHandler?(.failure(error))
            completionHandler = nil
        }
    }
}
