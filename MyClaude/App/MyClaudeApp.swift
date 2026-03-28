import SwiftUI

@main
struct MyClaudeApp: App {
    @State private var viewModel: UsageViewModel

    var body: some Scene {
        MenuBarExtra(viewModel.menuBarTitle, systemImage: "brain.head.profile") {
            MenuBarView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
        .defaultSize(width: 280, height: 500)
    }

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let vm = UsageViewModel()
        _viewModel = State(initialValue: vm)
        vm.start()
    }
}
