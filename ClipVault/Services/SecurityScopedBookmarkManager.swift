import Foundation

final class SecurityScopedBookmarkManager {
    func bookmark(for url: URL) throws -> Data { try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) }
    func resolve(_ data: Data) throws -> URL { var stale = false; return try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) }
    func withAccess<T>(to url: URL, _ work: () throws -> T) rethrows -> T { let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }; return try work() }
}
