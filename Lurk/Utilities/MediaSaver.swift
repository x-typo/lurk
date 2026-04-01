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
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
            let result = await saveToLibrary {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }
            try? FileManager.default.removeItem(at: fileURL)
            return result
        } catch {
            return .failed
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
}
