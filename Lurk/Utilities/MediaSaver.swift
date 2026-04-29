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
        await saveVideo(from: [url])
    }

    static func saveVideo(from urls: [URL]) async -> SaveResult {
        var lastResult: SaveResult = .failed
        for url in urls {
            do {
                let fileURL = try await temporaryVideoFile(from: url)
                let result = await saveToLibrary {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
                }
                try? FileManager.default.removeItem(at: fileURL)
                switch result {
                case .saved, .denied:
                    return result
                case .failed:
                    lastResult = result
                }
            } catch VideoExportError.blockedHost {
                return .failed
            } catch {
                lastResult = .failed
            }
        }
        return lastResult
    }

    static func temporaryVideoFile(from urls: [URL]) async throws -> URL {
        var lastError: Error?
        for url in urls {
            do {
                return try await temporaryVideoFile(from: url)
            } catch VideoExportError.blockedHost {
                throw VideoExportError.blockedHost
            } catch {
                lastError = error
            }
        }
        throw lastError ?? VideoExportError.noDownloadURL
    }

    static func temporaryVideoFile(from url: URL) async throws -> URL {
        guard !url.isYouTubeVideoDownloadURL else {
            throw VideoExportError.blockedHost
        }

        if url.pathExtension.lowercased() == "m3u8" {
            return try await exportVideo(from: url)
        }

        let (tempURL, response) = try await URLSession.shared.download(from: url)
        do {
            try validateDownloadResponse(response)
            let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
            return fileURL
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }

    private static func exportVideo(from url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let presetName = await preferredExportPreset(for: asset),
              let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
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

    private static func preferredExportPreset(for asset: AVAsset) async -> String? {
        for preset in [
            AVAssetExportPresetPassthrough,
            AVAssetExportPresetHighestQuality,
            AVAssetExportPresetMediumQuality
        ] {
            if await AVAssetExportSession.compatibility(ofExportPreset: preset, with: asset, outputFileType: nil) {
                return preset
            }
        }
        return nil
    }

    private static func validateDownloadResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            throw VideoExportError.badResponse
        }
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
        case blockedHost
        case noDownloadURL
        case badResponse
    }
}

private extension URL {
    var isYouTubeVideoDownloadURL: Bool {
        guard let host = host?.lowercased() else { return false }
        let normalizedHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return normalizedHost == "youtu.be"
            || normalizedHost == "youtube.com"
            || normalizedHost.hasSuffix(".youtube.com")
    }
}
