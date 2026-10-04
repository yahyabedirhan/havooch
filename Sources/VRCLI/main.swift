import Foundation
import VRCommand

// The `video-review` executable: everything it does is `CLI.run`.
let result = CLI.run(arguments: Array(CommandLine.arguments.dropFirst()), environment: .live())
FileHandle.standardOutput.write(Data(result.output.utf8))
FileHandle.standardError.write(Data(result.error.utf8))
exit(result.exitCode)
