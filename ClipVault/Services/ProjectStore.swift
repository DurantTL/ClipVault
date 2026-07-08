import Foundation

final class ProjectStore {
    static let metadataName = ".clipvault-project.json"
    func save(_ project: ClipVaultProject) throws {
        let url = URL(fileURLWithPath: project.projectFolderPath).appendingPathComponent(Self.metadataName)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
        try enc.encode(project).write(to: url, options: .atomic)
        addRecent(url)
    }
    func load(from folderOrFile: URL) throws -> ClipVaultProject {
        let url = folderOrFile.lastPathComponent == Self.metadataName ? folderOrFile : folderOrFile.appendingPathComponent(Self.metadataName)
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let p = try dec.decode(ClipVaultProject.self, from: Data(contentsOf: url)); addRecent(url); return p
    }
    func addRecent(_ url: URL) { var r = UserDefaults.standard.stringArray(forKey: "recentProjects") ?? []; r.removeAll { $0 == url.path }; r.insert(url.path, at: 0); UserDefaults.standard.set(Array(r.prefix(10)), forKey: "recentProjects") }
}
