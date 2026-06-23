import SwiftUI

/// Application settings panel
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("Основные", systemImage: "gearshape") }

            OutputSettingsView()
                .tabItem { Label("Вывод", systemImage: "doc") }

            AboutView()
                .tabItem { Label("О программе", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - General
private struct GeneralSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Form {
            Section("Модель") {
                Picker("Модель", selection: Bindable(settings).modelPath) {
                    ForEach(settings.availableModels, id: \.self) { name in
                        Text(name).tag(NSHomeDirectory() + "/.cache/whisper-cpp/" + name)
                    }
                }
                .pickerStyle(.menu)

                Button("Обновить список моделей") {
                    settings.scanModels()
                }
                .font(.caption)
            }

            Section("Язык") {
                Picker("Язык распознавания", selection: Bindable(settings).language) {
                    ForEach(settings.availableLanguages, id: \.id) { lang in
                        Text(lang.name).tag(lang.id)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Производительность") {
                HStack {
                    Text("Потоков:")
                    Spacer()
                    Picker("", selection: Bindable(settings).threads) {
                        ForEach([1, 2, 4, 6, 8, 10], id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                }

                HStack {
                    Text("GPU устройство:")
                    Spacer()
                    Picker("", selection: Bindable(settings).gpuDevice) {
                        Text("Основной (0)").tag(0)
                        Text("Дополнительный (1)").tag(1)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200)
                }
            }
        }
        .padding()
        .formStyle(.grouped)
    }
}

// MARK: - Output
private struct OutputSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Form {
            Section("Форматы вывода") {
                Toggle("TXT (текст)", isOn: Bindable(settings).outputTxt)
                Toggle("SRT (субтитры)", isOn: Bindable(settings).outputSrt)
                Toggle("VTT (веб-субтитры)", isOn: Bindable(settings).outputVtt)
                Toggle("JSON (структурированные данные)", isOn: Bindable(settings).outputJson)
                Toggle("CSV (таблица)", isOn: Bindable(settings).outputCsv)
            }

            Section("Папка сохранения") {
                HStack {
                    TextField("Путь", text: Bindable(settings).outputDir)
                        .textFieldStyle(.roundedBorder)

                    Button("Выбрать") {
                        selectOutputFolder()
                    }
                }

                Button("Открыть папку") {
                    let url = URL(fileURLWithPath: settings.outputDir)
                    NSWorkspace.shared.open(url)
                }
                .font(.caption)
            }
        }
        .padding()
        .formStyle(.grouped)
        .onAppear {
            ensureOutputDirExists()
        }
    }

    private func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "Выберите папку для сохранения транскриптов"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.outputDir = url.path
    }

    private func ensureOutputDirExists() {
        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: settings.outputDir),
            withIntermediateDirectories: true
        )
    }
}

// MARK: - About
private struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "waveform")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("whisper-gui")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Версия 1.0.0")
                .foregroundColor(.secondary)

            Divider()
                .frame(width: 200)

            VStack(alignment: .leading, spacing: 6) {
                Label("Движок: whisper-cpp (Metal GPU)", systemImage: "cpu")
                Label("Загрузка: yt-dlp", systemImage: "video.fill")
                Label("Конвертация: ffmpeg", systemImage: "arrow.triangle.swap")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
