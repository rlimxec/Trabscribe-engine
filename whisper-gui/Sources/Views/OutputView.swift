import SwiftUI

/// Shows transcription result with copy and save options
struct OutputView: View {
    let text: String
    let files: [URL]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundColor(.accentColor)
                Text("Результат транскрибации")
                    .font(.headline)
                Spacer()

                Button("Копировать") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .help("Копировать текст в буфер обмена")

                if let firstFile = files.first {
                    Button("Показать в Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([firstFile])
                    }
                    .help("Открыть папку с файлами")
                }
            }

            if !text.isEmpty {
                ScrollView {
                    Text(text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(maxHeight: 300)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
            }

            if !files.isEmpty {
                HStack {
                    Text("Файлы:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(files, id: \.self) { file in
                        Text(file.lastPathComponent)
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                }
            }
        }
    }
}
