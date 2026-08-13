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
            let fileURL = try await temporaryGIFFile(from: url)
            defer { try? FileManager.default.removeItem(at: fileURL) }
            try Task.checkCancellation()
            let result = await saveToLibrary {
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
            }
            return result
        } catch {
            return .failed
        }
    }

    nonisolated static func temporaryGIFFile(from url: URL) async throws -> URL {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }

        let (bytes, response) = try await session.bytes(from: url)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).gif")
        try await writeGIFDownload(bytes: bytes, response: response, to: fileURL)
        return fileURL
    }

    @concurrent
    nonisolated static func writeGIFDownload<Bytes: AsyncSequence & Sendable>(
        bytes: Bytes,
        response: URLResponse,
        to fileURL: URL,
        maximumEncodedBytes: Int = GIFDecoder.Limits.default.maximumEncodedBytes
    ) async throws where Bytes.Element == UInt8 {
        guard maximumEncodedBytes > 0,
              let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              response.expectedContentLength <= 0
                || response.expectedContentLength <= Int64(maximumEncodedBytes) else {
            throw GIFDownloadError.invalidDownload
        }
        guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
            throw GIFDownloadError.fileCreationFailed
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forWritingTo: fileURL)
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            throw error
        }
        do {
            var buffer = Data()
            buffer.reserveCapacity(64 * 1_024)
            var signature = Data()
            var totalBytes = 0

            try Task.checkCancellation()
            for try await byte in bytes {
                guard totalBytes < maximumEncodedBytes else {
                    throw GIFDownloadError.encodedDataTooLarge
                }
                totalBytes += 1
                if signature.count < 6 {
                    signature.append(byte)
                }
                buffer.append(byte)

                if buffer.count >= 64 * 1_024 {
                    try handle.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                    try Task.checkCancellation()
                }
            }
            try Task.checkCancellation()
            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
            }
            try handle.close()

            guard isValidGIFDownload(
                response: response,
                fileSize: totalBytes,
                signature: signature,
                maximumEncodedBytes: maximumEncodedBytes
            ) else {
                throw GIFDownloadError.invalidDownload
            }
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: fileURL)
            throw error
        }
    }

    nonisolated static func isValidGIFDownload(
        response: URLResponse,
        fileSize: Int,
        signature: Data,
        maximumEncodedBytes: Int = GIFDecoder.Limits.default.maximumEncodedBytes
    ) -> Bool {
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              fileSize > 0,
              fileSize <= maximumEncodedBytes else {
            return false
        }
        return signature == Data("GIF87a".utf8) || signature == Data("GIF89a".utf8)
    }

    static func saveVideo(from url: URL) async -> SaveResult {
        await saveVideo(from: [url])
    }

    static func saveVideo(from urls: [URL]) async -> SaveResult {
        var lastResult: SaveResult = .failed
        for url in urls {
            guard !Task.isCancelled else { return .failed }
            do {
                let fileURL = try await temporaryVideoFile(from: url)
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: fileURL)
                    return .failed
                }
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
            } catch {
                guard !Task.isCancelled else { return .failed }
                lastResult = .failed
            }
        }
        return lastResult
    }

    static func temporaryVideoFile(from urls: [URL]) async throws -> URL {
        try await firstTemporaryVideoFile(from: urls) { url in
            try await temporaryVideoFile(from: url)
        }
    }

    static func firstTemporaryVideoFile(
        from urls: [URL],
        download: (URL) async throws -> URL
    ) async throws -> URL {
        var lastError: Error?
        for url in urls {
            try Task.checkCancellation()
            do {
                return try await download(url)
            } catch {
                try Task.checkCancellation()
                lastError = error
            }
        }
        throw lastError ?? VideoExportError.noDownloadURL
    }

    static func temporaryVideoFile(from url: URL) async throws -> URL {
        try Task.checkCancellation()
        guard !url.isYouTubeVideoDownloadURL else {
            throw VideoExportError.blockedHost
        }

        if url.pathExtension.lowercased() == "m3u8" {
            return try await exportVideo(from: url)
        }

        let (tempURL, response) = try await URLSession.shared.download(from: url)
        do {
            try Task.checkCancellation()
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
        return try await keepTemporaryFileOnSuccess(at: fileURL) {
            try await exportSession.export(to: fileURL, as: fileType)
        }
    }

    static func keepTemporaryFileOnSuccess(
        at fileURL: URL,
        operation: () async throws -> Void
    ) async throws -> URL {
        do {
            try await operation()
            try Task.checkCancellation()
            return fileURL
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            throw error
        }
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

    private enum GIFDownloadError: Error {
        case invalidDownload
        case fileCreationFailed
        case encodedDataTooLarge
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
