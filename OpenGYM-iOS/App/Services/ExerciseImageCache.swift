import Foundation
import ImageIO
import UIKit

/// Catalogue images, like videos, are public and identified by stable exercise IDs.
/// Keep validated originals in Documents so they remain available offline and in Files.
actor ExerciseImageCache {
    static let shared = ExerciseImageCache()
    static let documentsFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("workout-images", isDirectory: true)
    private static let maximumFileSize = 2 * 1024 * 1024

    nonisolated let directory: URL
    private let session: URLSession
    private let maximumDownloads: Int
    private var downloads: [String: Task<UIImage, Error>] = [:]
    private var activeDownloads = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(directory: URL = ExerciseImageCache.documentsFolder, session: URLSession = .shared, maximumDownloads: Int = 4) {
        self.directory = directory
        self.session = session
        self.maximumDownloads = max(1, maximumDownloads)
    }

    nonisolated func cachedURL(for id: String) -> URL? {
        guard let file = destination(for: id),
              let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= Self.maximumFileSize else { return nil }
        return file
    }

    private nonisolated func destination(for id: String) -> URL? {
        guard (4...5).contains(id.utf8.count), id.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return directory.appendingPathComponent(id).appendingPathExtension("webp")
    }

    func image(for id: String, remoteURL: URL?) async throws -> UIImage {
        guard let destination = destination(for: id) else { throw URLError(.badURL) }
        if let existing = downloads[id] { return try await existing.value }
        // An individual disappearing cell must not cancel a shared download.
        // Actor isolation also keeps disk reads and image decoding off the main actor.
        let task = Task { try await load(id: id, destination: destination, remoteURL: remoteURL) }
        downloads[id] = task
        defer { downloads[id] = nil }
        return try await task.value
    }

    private func load(id: String, destination: URL, remoteURL: URL?) async throws -> UIImage {
        if let cached = cachedURL(for: id), let image = Self.decode(cached) { return image }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        guard let remoteURL else { throw URLError(.badURL) }
        await acquireDownloadSlot()
        defer { releaseDownloadSlot() }
        let (temporary, response) = try await session.download(from: remoteURL)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= Self.maximumFileSize,
              let image = Self.decode(temporary) else { throw URLError(.badServerResponse) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        // Publish only a fully downloaded, decoded file, using write-then-rename.
        try Data(contentsOf: temporary).write(to: destination, options: .atomic)
        return image
    }

    private func acquireDownloadSlot() async {
        if activeDownloads < maximumDownloads {
            activeDownloads += 1
        } else {
            await withCheckedContinuation { waiting.append($0) }
        }
    }

    private func releaseDownloadSlot() {
        if waiting.isEmpty {
            activeDownloads -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }

    private static func decode(_ file: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              CGImageSourceGetCount(source) == 1,
              CGImageSourceGetStatus(source) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...4096).contains(width), (1...4096).contains(height),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
