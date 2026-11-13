import Foundation

@main
struct ImageTool {
    static func main() async throws {
        let args = CommandLine.arguments.dropFirst()
        guard let path = args.first else {
            print("usage: imagetool <path>")
            return
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        print("Read \(data.count) bytes")
    }
}
