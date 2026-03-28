import SwiftUI

@main
struct MyClaudeApp: App {
    @State private var viewModel = UsageViewModel()

    var body: some Scene {
        MenuBarExtra(viewModel.menuBarTitle, systemImage: "brain.head.profile") {
            MenuBarView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
        .defaultSize(width: 280, height: 500)
        .onChange(of: viewModel.menuBarTitle) { _, _ in }
    }

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
