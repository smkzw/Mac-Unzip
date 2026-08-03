import Darwin
import Foundation
import HelperSpike

guard CommandLine.arguments.count == 2 else { exit(64) }
let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
for descriptor in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] {
    _ = Darwin.close(descriptor)
}

Task {
    var password = SecureBytes(Array("low-fd-harness".utf8))
    do {
        let result = try await HelperLauncher().run(
            executable: fixture,
            arguments: ["--password-lines", "1"],
            password: &password,
            promptSequence: .passwordLines(1),
            limits: .testDefault
        )
        exit(result.termination == .exited(0) && result.directChildReaped && result.processGroupGone ? 0 : 1)
    } catch {
        exit(2)
    }
}
dispatchMain()
