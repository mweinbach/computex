import Foundation
import Virtualization

final class RestoreImageDownloader: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var progressHandler: ((Double) -> Void)?
    private var destinationURL: URL?
    private var session: URLSession?

    func downloadLatestIfNeeded(to destinationURL: URL, progress: @escaping (Double) -> Void) async throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            AppLog.info("Restore image already exists at \(destinationURL.path).")
            return
        }

        AppLog.info("Fetching latest supported restore image.")
        let restoreImage = try await fetchLatestRestoreImage()
        AppLog.info("Downloading restore image from \(restoreImage.url.absoluteString).")
        try await download(url: restoreImage.url, to: destinationURL, progress: progress)
    }

    private func fetchLatestRestoreImage() async throws -> VZMacOSRestoreImage {
        try await withCheckedThrowingContinuation { continuation in
            VZMacOSRestoreImage.fetchLatestSupported { result in
                switch result {
                case .success(let image):
                    AppLog.info("Fetched latest supported restore image.")
                    continuation.resume(returning: image)
                case .failure(let error):
                    AppLog.error("Failed to fetch restore image: \(error.localizedDescription)")
                    continuation.resume(throwing: VMError.restoreImageDownloadFailed(error.localizedDescription))
                }
            }
        }
    }

    private func download(
        url: URL,
        to destinationURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws {
        progressHandler = progress
        self.destinationURL = destinationURL

        let configuration = URLSessionConfiguration.default
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
        self.session = session

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            let task = session.downloadTask(with: url)
            AppLog.info("Restore image download task started.")
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else {
            progressHandler?(0)
            return
        }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler?(fraction)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let destinationURL else {
            AppLog.error("Missing destination URL for restore image download.")
            finish(.failure(VMError.restoreImageDownloadFailed("Missing destination URL")))
            return
        }

        do {
            try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)
            progressHandler?(1.0)
            AppLog.info("Restore image downloaded to \(destinationURL.path).")
            finish(.success(()))
        } catch {
            AppLog.error("Restore image download move failed: \(error.localizedDescription)")
            finish(.failure(VMError.restoreImageDownloadFailed(error.localizedDescription)))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            AppLog.error("Restore image download failed: \(error.localizedDescription)")
            finish(.failure(VMError.restoreImageDownloadFailed(error.localizedDescription)))
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        session?.invalidateAndCancel()
        session = nil
        destinationURL = nil
        progressHandler = nil
        continuation.resume(with: result)
    }
}
