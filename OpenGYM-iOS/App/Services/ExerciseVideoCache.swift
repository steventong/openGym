import AVFoundation
import Foundation

/// Catalogue IDs identify the same public clips across accounts and servers.
/// Only complete, playable files are published in the Files-visible directory.
actor ExerciseVideoCache {
    static let shared = ExerciseVideoCache()
    static let documentsFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("workout-videos", isDirectory: true)

    nonisolated let directory: URL
    private let session: URLSession
    private var downloads: [String: Task<URL, Error>] = [:]

    init(directory: URL = ExerciseVideoCache.documentsFolder, session: URLSession = .shared) {
        self.directory = directory
        self.session = session
    }

    nonisolated func cachedURL(for id: String) -> URL? {
        guard let file = destination(for: id),
              let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? 0) > 0 else { return nil }
        return file
    }

    private nonisolated func destination(for id: String) -> URL? {
        guard id.range(of: "^[0-9]{4,5}$", options: .regularExpression) != nil else { return nil }
        return directory.appendingPathComponent(id).appendingPathExtension("mp4")
    }

    func video(for id: String, remoteURL: URL?) async throws -> URL {
        guard let destination = destination(for: id) else { throw URLError(.badURL) }
        if let existing = downloads[id] { return try await existing.value }
        let cached = cachedURL(for: id)
        let directory = directory
        let session = session
        // A view disappearing cancels its playback, but lets the shared download
        // finish so reopening the exercise can use the cached file.
        let task = Task<URL, Error> {
            if let cached, await Self.isPlayable(cached) { return cached }
            if cached != nil { try? FileManager.default.removeItem(at: destination) }
            guard let remoteURL else { throw URLError(.badURL) }
            let (temporary, response) = try await session.download(from: remoteURL)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
            // URLSession's .tmp suffix is not a media type AVFoundation can
            // reliably recognize. Validate an MP4 staging file outside Documents.
            let staged = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
            try FileManager.default.moveItem(at: temporary, to: staged)
            defer { try? FileManager.default.removeItem(at: staged) }
            guard await Self.isPlayable(staged) else { throw URLError(.badServerResponse) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var folder = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
            // Move only after validation; partial downloads never become cache hits.
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: staged, to: destination)
            return destination
        }
        downloads[id] = task
        defer { downloads[id] = nil }
        return try await task.value
    }

    private static func isPlayable(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        do {
            let playable = try await asset.load(.isPlayable)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            return playable && !tracks.isEmpty
        } catch { return false }
    }
}
