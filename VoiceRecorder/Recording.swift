import Foundation

struct Recording: Identifiable {
    let id = UUID()
    let url: URL
    let date: Date
    let transcript: String?

    var name: String {
        url.deletingPathExtension().lastPathComponent
    }

    var transcriptURL: URL? {
        let txtURL = url.deletingPathExtension().appendingPathExtension("txt")
        return FileManager.default.fileExists(atPath: txtURL.path) ? txtURL : nil
    }
}
