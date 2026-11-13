import SwiftUI

enum AppTheme: String {
    case system, light, dark

    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@main
struct ThemedApp: App {
    @AppStorage("theme") private var theme: AppTheme = .system

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(theme.scheme)
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            PromoBanner()
                .preferredColorScheme(.light)   // banner artwork only looks right on light
            ReaderPane()
                .preferredColorScheme(.dark)    // reader should always be dark
        }
    }
}

struct PromoBanner: View {
    var body: some View {
        Text("Try Premium")
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(.background)
    }
}

struct ReaderPane: View {
    var body: some View {
        ScrollView {
            Text("Chapter 1")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(.background)
    }
}
