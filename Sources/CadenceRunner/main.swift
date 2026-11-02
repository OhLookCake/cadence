import Foundation
import CadenceCore

let args = Array(CommandLine.arguments.dropFirst())
func value(_ key: String) -> String? {
    guard let index = args.firstIndex(of: key), args.indices.contains(index + 1) else { return nil }
    return args[index + 1]
}
do {
    guard let raw = value("--task"), let id = UUID(uuidString: raw) else {
        throw CadenceError.message("Usage: CadenceRunner --task UUID [--manual] [--data-dir PATH]")
    }
    let store = try CadenceStore(root: value("--data-dir").map { URL(fileURLWithPath: $0) })
    try TaskRunner.run(store: store, id: id, manual: args.contains("--manual"))
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1)
}
