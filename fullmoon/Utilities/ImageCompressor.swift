//
//  ImageCompressor.swift
//  Navi
//
//  Image compression utilities for Navi.
//  Compresses images before sending to model or storing in SwiftData.
//

import UIKit

enum ImageCompressor {
    /// Compress image for model inference (maintain reasonable resolution)
    static func compressForInference(
        _ image: UIImage,
        maxSize: CGSize = CGSize(width: 1024, height: 1024)
    ) -> Data? {
        let scaled = scaleImage(image, to: maxSize)
        return scaled.jpegData(compressionQuality: 0.7)
    }

    /// Compress image for chat record thumbnail storage
    static func compressForThumbnail(_ image: UIImage) -> Data? {
        let thumbnail = scaleImage(image, to: CGSize(width: 200, height: 200))
        return thumbnail.jpegData(compressionQuality: 0.5)
    }

    /// Scale image to fit within maxSize, maintaining aspect ratio, never upscale
    private static func scaleImage(_ image: UIImage, to maxSize: CGSize) -> UIImage {
        let size = image.size
        let widthRatio = maxSize.width / size.width
        let heightRatio = maxSize.height / size.height
        let ratio = min(widthRatio, heightRatio, 1.0)  // Don't upscale

        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
