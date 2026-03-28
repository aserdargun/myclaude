import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = UsageViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        viewModel.start()
    }
}

@main
struct MyClaudeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(viewModel: appDelegate.viewModel)
        } label: {
            Text(appDelegate.viewModel.menuBarTitle)
                .font(.system(size: 11))
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)
        .defaultSize(width: 340, height: 500)
    }
}
