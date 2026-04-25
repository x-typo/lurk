import AVFoundation
import Photos
import UIKit

enum MediaSaver {
    enum SaveResult {
        case saved, denied, failed
    }

    static func saveImage(from url: URL) async -> SaveResult {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return .failed }
            return await saveToLibrary {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        } catch {
            return .failed
        }
    }

    static func saveImageData(from url: URL) async -> SaveResult {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let ext = url.pathExtension.isEmpty ? "gif" : url.pathExtension
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
            try data.write(to: fileURL)
            let result = await saveToLibrary {
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
            }
            try? FileManager.default.removeItem(at: fileURL)
            return result
        } catch {
            return .failed
        }
    }

    static func saveVideo(from url: URL) async -> SaveResult {
        do {
            let fileURL = try await temporaryVideoFile(from: url)
            let result = await saveToLibrary {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }
            try? FileManager.default.removeItem(at: fileURL)
            return result
        } catch {
            return .failed
        }
    }

    static func temporaryVideoFile(from url: URL) async throws -> URL {
        if url.pathExtension.lowercased() == "m3u8" {
            return try await exportVideo(from: url)
        }

        let (tempURL, _) = try await URLSession.shared.download(from: url)
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        try FileManager.default.moveItem(at: tempURL, to: fileURL)
        return fileURL
    }

    private static func exportVideo(from url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoExportError.exportSessionUnavailable
        }

        let fileType: AVFileType
        let ext: String
        if exportSession.supportedFileTypes.contains(.mp4) {
            fileType = .mp4
            ext = "mp4"
        } else if exportSession.supportedFileTypes.contains(.mov) {
            fileType = .mov
            ext = "mov"
        } else {
            throw VideoExportError.unsupportedFileType
        }

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        exportSession.shouldOptimizeForNetworkUse = true
        try await exportSession.export(to: fileURL, as: fileType)
        return fileURL
    }

    private static func saveToLibrary(_ changeBlock: @escaping () -> Void) async -> SaveResult {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return .denied }

        do {
            try await PHPhotoLibrary.shared().performChanges(changeBlock)
            return .saved
        } catch {
            return .failed
        }
    }

    private enum VideoExportError: Error {
        case exportSessionUnavailable
        case unsupportedFileType
    }
}
