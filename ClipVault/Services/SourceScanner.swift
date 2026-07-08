import Foundation

final class SourceScanner {
    static let supported = Set(["mov","mp4","m4v","mts","m2ts","mxf","avi","hevc","h264"])
    func scan(source: URL, includeProxyFiles: Bool) throws -> [SourceVideo] {
        let fm = FileManager.default
        let sonyClip = source.appendingPathComponent("PRIVATE/M4ROOT/CLIP")
        let roots = fm.fileExists(atPath: sonyClip.path) ? [sonyClip] : [source]
        var out: [SourceVideo] = []
        for root in roots {
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isHiddenKey,.fileSizeKey,.creationDateKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in e {
                if !includeProxyFiles && url.path.contains("/PRIVATE/M4ROOT/SUB/") { continue }
                guard Self.supported.contains(url.pathExtension.lowercased()) else { continue }
                let rv = try url.resourceValues(forKeys: [.isHiddenKey,.fileSizeKey,.creationDateKey])
                if rv.isHidden == true || url.lastPathComponent.hasPrefix(".") { continue }
                let relBase = source.standardizedFileURL.path
                let rel = url.standardizedFileURL.path.replacingOccurrences(of: relBase + "/", with: "")
                out.append(SourceVideo(url: url, relativePath: rel, size: Int64(rv.fileSize ?? 0), createdAt: rv.creationDate))
            }
        }
        return out.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }
}
