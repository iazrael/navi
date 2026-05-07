//
//  ModelDownloader.swift
//  Navi
//
//  Downloads .litertlm model files with progress tracking and cancellation support.
//

import Foundation
import Observation

@Observable
@MainActor
final class ModelDownloader {
    /// Current download progress (0.0 to 1.0)
    var downloadProgress: Double = 0.0
    
    /// Whether a download is currently in progress
    var isDownloading: Bool = false
    
    /// Error message if download failed
    var errorMessage: String?
    
    /// Current download task (for cancellation)
    private var currentTask: Task<Void, Never>?
    
    /// Active URLSession download task
    private var urlSessionTask: URLSessionDownloadTask?
    
    // MARK: - Public API
    
    /// Download a model file
    /// - Parameters:
    ///   - model: The NaviModel to download
    ///   - onProgress: Optional callback with progress (0.0 to 1.0)
    ///   - onCompletion: Called when download completes (success) or fails (error)
    func download(model: NaviModel) async throws {
        let destinationURL = modelDestinationURL(for: model)
        
        // Check if already downloaded
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            downloadProgress = 1.0
            return
        }
        
        guard let url = URL(string: model.downloadURL) else {
            throw DownloadError.invalidURL
        }
        
        isDownloading = true
        downloadProgress = 0.0
        errorMessage = nil
        
        do {
            try await performDownload(from: url, to: destinationURL, expectedSize: model.sizeMB)
            downloadProgress = 1.0
        } catch is CancellationError {
            // Clean up partial download
            try? FileManager.default.removeItem(at: destinationURL)
            downloadProgress = 0.0
        } catch {
            errorMessage = error.localizedDescription
            // Clean up partial download
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
        
        isDownloading = false
    }
    
    /// Cancel the active download
    func cancel() {
        urlSessionTask?.cancel()
        urlSessionTask = nil
        currentTask?.cancel()
        currentTask = nil
        isDownloading = false
        downloadProgress = 0.0
    }
    
    /// Check if a model is already downloaded
    func isModelDownloaded(_ model: NaviModel) -> Bool {
        let destinationURL = modelDestinationURL(for: model)
        return FileManager.default.fileExists(atPath: destinationURL.path)
    }
    
    /// Delete a downloaded model file
    func deleteModel(_ model: NaviModel) throws {
        let destinationURL = modelDestinationURL(for: model)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
    }
    
    // MARK: - Private
    
    private func modelDestinationURL(for model: NaviModel) -> URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDir.appendingPathComponent(model.fileName)
    }
    
    private func performDownload(from url: URL, to destination: URL, expectedSize: Int) async throws {
        let tempDestination = destination.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString + ".tmp")
        
        let observation = AsyncStream<URLSessionDownloadTask>.makeStream(of: URLSessionDownloadTask.self)
        
        let delegate = DownloadDelegate(
            expectedBytes: Int64(expectedSize) * 1024 * 1024,
            onProgress: { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress
                }
            }
        )
        
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        urlSessionTask = session.downloadTask(with: url)
        
        guard let task = urlSessionTask else {
            throw DownloadError.failedToCreateTask
        }
        
        task.resume()
        
        let tempURL: URL = try await withCheckedThrowingContinuation { continuation in
            delegate.completion = continuation
        }
        
        // Move temp file to final destination
        // Remove existing file if any
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        
        session.invalidateAndCancel()
    }
    
    enum DownloadError: LocalizedError {
        case invalidURL
        case failedToCreateTask
        case downloadCancelled
        case diskSpaceInsufficient
        
        var errorDescription: String? {
            switch self {
            case .invalidURL: "Invalid download URL"
            case .failedToCreateTask: "Failed to create download task"
            case .downloadCancelled: "Download was cancelled"
            case .diskSpaceInsufficient: "Not enough disk space"
            }
        }
    }
}

// MARK: - URLSession Download Delegate

private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let expectedBytes: Int64
    private let onProgress: (Double) -> Void
    var completion: CheckedContinuation<URL, Error>?
    
    init(expectedBytes: Int64, onProgress: @escaping (Double) -> Void) {
        self.expectedBytes = expectedBytes
        self.onProgress = onProgress
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Copy to a temp file we control (system deletes `location` after delegate returns)
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".download")
        do {
            try FileManager.default.copyItem(at: location, to: tempFile)
            completion?.resume(returning: tempFile)
        } catch {
            completion?.resume(throwing: error)
        }
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedBytes
        let progress = Double(totalBytesWritten) / Double(expected)
        onProgress(min(progress, 1.0))
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            completion?.resume(throwing: error)
        }
    }
}
