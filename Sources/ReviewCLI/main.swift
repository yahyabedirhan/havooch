import Foundation
import ReviewCommand

let result = HavoochCLI.run(
    Array(CommandLine.arguments.dropFirst()),
    environment: .live(executable: Bundle.main.executableURL)
)
FileHandle.standardOutput.write(Data(result.output.utf8))
FileHandle.standardError.write(Data(result.error.utf8))
exit(result.exitCode)
