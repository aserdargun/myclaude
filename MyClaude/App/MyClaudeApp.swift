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
        MenuBarExtra(appDelegate.viewModel.menuBarTitle, systemImage: "brain.head.profile") {
            MenuBarView(viewModel: appDelegate.viewModel)
        }
        .menuBarExtraStyle(.window)
        .defaultSize(width: 280, height: 500)
    }
}
