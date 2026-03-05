import Foundation

enum FileNaming {
    static func generate(prefix: String = "Screenshot") -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(prefix) \(formatter.string(from: Date()))"
    }
}
