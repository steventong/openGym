#!/usr/bin/env swift
// Run from any directory: swift native-ios/scripts/build-thumbnails.swift
// Uses macOS ImageIO; no third-party image tooling is required.
import Foundation
import ImageIO
import UniformTypeIdentifiers

let manager = FileManager.default
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let source = root.appendingPathComponent("catalogue/media/thumbnails")
let destination = root.appendingPathComponent("native-ios/OpenGym/Resources/Assets.xcassets/ExerciseThumbnails")
let naming = Process()
naming.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
naming.arguments = [root.appendingPathComponent("native-ios/scripts/thumbnail_assets.py").path]
let namesPipe = Pipe()
naming.standardOutput = namesPipe
try naming.run()
let namesData = namesPipe.fileHandleForReading.readDataToEndOfFile()
naming.waitUntilExit()
guard naming.terminationStatus == 0 else { fatalError("Cannot generate English asset names") }
let assetNames = try JSONDecoder().decode([String: String].self, from: namesData)
let files = try manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "webp" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
guard !files.isEmpty else { fatalError("No source thumbnails found at \(source.path)") }

func writeJSON(_ value: [String: Any], to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    try (data + Data("\n".utf8)).write(to: url, options: .atomic)
}

let info: [String: Any] = ["author": "xcode", "version": 1]
try manager.createDirectory(at: destination, withIntermediateDirectories: true)
try writeJSON(["info": info, "properties": ["provides-namespace": true]],
              to: destination.appendingPathComponent("Contents.json"))
for file in files {
    try autoreleasepool {
        guard let sourceImage = CGImageSourceCreateWithURL(file as CFURL, nil),
              CGImageSourceGetCount(sourceImage) == 1,
              let image = CGImageSourceCreateImageAtIndex(sourceImage, 0, nil) else {
            fatalError("Expected a static image: \(file.path)")
        }
        let id = file.deletingPathExtension().lastPathComponent
        guard let resourceName = assetNames[id]?.split(separator: "/").last else {
            fatalError("Missing English asset name for \(id)")
        }
        let name = String(resourceName)
        let asset = destination.appendingPathComponent("\(name).imageset")
        try manager.createDirectory(at: asset, withIntermediateDirectories: true)
        let png = asset.appendingPathComponent("\(name).png")
        guard let output = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            fatalError("Cannot create \(png.path)")
        }
        CGImageDestinationAddImage(output, image, nil)
        guard CGImageDestinationFinalize(output) else { fatalError("Cannot write \(png.path)") }
        try writeJSON(["images": [["filename": "\(name).png", "idiom": "universal", "scale": "1x"]], "info": info],
                      to: asset.appendingPathComponent("Contents.json"))
    }
}
// Remove only obsolete generated image sets after every replacement was written successfully.
let expected = Set(assetNames.values.map { String($0.split(separator: "/").last!) + ".imageset" })
for old in try manager.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)
    where old.pathExtension == "imageset" && !expected.contains(old.lastPathComponent) {
    try manager.removeItem(at: old)
}
print("Prepared \(files.count) PNG thumbnail image sets in \(destination.path)")
