import Foundation
import VRCommand

// The `video-review` command: runs the table, prints, exits.
let result = CommandTable.standard.run(Array(CommandLine.arguments.dropFirst()), environment: .system())
FileHandle.standardOutput.write(Data(result.output.utf8))
FileHandle.standardError.write(Data(result.error.utf8))
exit(result.status)
