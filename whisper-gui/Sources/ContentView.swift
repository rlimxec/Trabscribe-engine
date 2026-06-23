import SwiftUI

struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @State private var selectedTab: Tab = .files

    enum Tab: String, CaseIterable, Identifiable {
        case files = "Файлы"
        case youtube = "YouTube"
        case microphone = "Микрофон"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .files: return "doc.text"
            case .youtube: return "video.fill"
            case .microphone: return "mic.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            TabView(selection: $selectedTab) {
                FileTabView()
                    .tag(Tab.files)
                    .tabItem { Label("Файлы", systemImage: "doc.text") }

                YouTubeTabView()
                    .tag(Tab.youtube)
                    .tabItem { Label("YouTube", systemImage: "video.fill") }

                MicTabView()
                    .tag(Tab.microphone)
                    .tabItem { Label("Микрофон", systemImage: "mic.fill") }
            }
            .tabViewStyle(.automatic)
        }
    }
}
