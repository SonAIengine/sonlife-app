import SwiftUI

@main
struct VoiceRecorderApp: App {
    @AppStorage("appTheme") private var selectedTheme: String = AppTheme.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(AppTheme(rawValue: selectedTheme)?.colorScheme)
        }
    }
}
