import Foundation
import SwiftUI

/// Global app settings, persisted in UserDefaults
@Observable
final class AppSettings {
    // MARK: - Singleton
    nonisolated(unsafe) static let shared = AppSettings()

    // MARK: - Persisted properties (UserDefaults)
    var modelPath: String {
        didSet { UserDefaults.standard.set(modelPath, forKey: "modelPath") }
    }
    var language: String {
        didSet { UserDefaults.standard.set(language, forKey: "language") }
    }
    var outputDir: String {
        didSet { UserDefaults.standard.set(outputDir, forKey: "outputDir") }
    }
    var threads: Int {
        didSet { UserDefaults.standard.set(threads, forKey: "threads") }
    }
    var gpuDevice: Int {
        didSet { UserDefaults.standard.set(gpuDevice, forKey: "gpuDevice") }
    }
    var outputTxt: Bool {
        didSet { UserDefaults.standard.set(outputTxt, forKey: "fmtTxt") }
    }
    var outputSrt: Bool {
        didSet { UserDefaults.standard.set(outputSrt, forKey: "fmtSrt") }
    }
    var outputVtt: Bool {
        didSet { UserDefaults.standard.set(outputVtt, forKey: "fmtVtt") }
    }
    var outputJson: Bool {
        didSet { UserDefaults.standard.set(outputJson, forKey: "fmtJson") }
    }
    var outputCsv: Bool {
        didSet { UserDefaults.standard.set(outputCsv, forKey: "fmtCsv") }
    }

    // MARK: - Derived
    var availableModels: [String] = []
    var availableLanguages: [(id: String, name: String)] = [
        ("auto", "Автоопределение"),
        ("ru", "Русский"),
        ("en", "English"),
    ]

    var activeFormats: Set<String> {
        var formats: Set<String> = []
        if outputTxt { formats.insert("txt") }
        if outputSrt { formats.insert("srt") }
        if outputVtt { formats.insert("vtt") }
        if outputJson { formats.insert("json") }
        if outputCsv { formats.insert("csv") }
        return formats
    }

    // MARK: - Defaults
    static let defaultModelPath = NSHomeDirectory() + "/.cache/whisper-cpp/ggml-large-v3-turbo.bin"
    static let defaultOutputDir = NSHomeDirectory() + "/Documents/Transcripts"

    // MARK: - Init
    private init() {
        let defaults = UserDefaults.standard

        self.modelPath = defaults.string(forKey: "modelPath") ?? Self.defaultModelPath
        self.language = defaults.string(forKey: "language") ?? "auto"
        self.outputDir = defaults.string(forKey: "outputDir") ?? Self.defaultOutputDir
        self.threads = defaults.object(forKey: "threads") as? Int ?? 4
        self.gpuDevice = defaults.object(forKey: "gpuDevice") as? Int ?? 0
        self.outputTxt = defaults.object(forKey: "fmtTxt") as? Bool ?? true
        self.outputSrt = defaults.object(forKey: "fmtSrt") as? Bool ?? false
        self.outputVtt = defaults.object(forKey: "fmtVtt") as? Bool ?? false
        self.outputJson = defaults.object(forKey: "fmtJson") as? Bool ?? false
        self.outputCsv = defaults.object(forKey: "fmtCsv") as? Bool ?? false

        scanModels()
    }

    // MARK: - Model scanning
    func scanModels() {
        let cacheDir = NSHomeDirectory() + "/.cache/whisper-cpp/"
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: cacheDir) else {
            availableModels = []
            return
        }
        availableModels = files
            .filter { $0.hasPrefix("ggml-") && $0.hasSuffix(".bin") }
            .sorted()
    }

    /// Ensure output directory exists
    func ensureOutputDir() throws {
        let url = URL(fileURLWithPath: outputDir)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
