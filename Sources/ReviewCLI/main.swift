import Foundation
import ReviewCommand

// The `video-review` executable: runs the command table with the real
// environment, prints what it answers and exits with its code.
let result = VideoReviewCLI.run(
    Array(CommandLine.arguments.dropFirst()),
    environment: .live(executable: Bundle.main.executableURL)
)
FileHandle.standardOutput.write(Data(result.output.utf8))
FileHandle.standardError.write(Data(result.error.utf8))
exit(result.exitCode)
