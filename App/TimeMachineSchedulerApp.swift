import SwiftUI

@main
struct TimeMachineSchedulerApp: App {
    var body: some Scene {
        Window("Time Machine Scheduler", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands {
            AppMenuCommands()
        }
    }
}
