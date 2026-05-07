//
//  ImageCompressorTests.swift
//  fullmoonTests
//
//  Sprint 5.4: Tests for ImageCompressor - compression size and quality.
//

import Testing
import UIKit
@testable import fullmoon

struct ImageCompressorTests {
    
    // MARK: - Helper
    
    private func makeTestImage(width: CGFloat, height: CGFloat) -> UIImage {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
    
    // MARK: - Inference Compression Tests
    
    @Test("Compress for inference reduces large images")
    func compressForInferenceReducesSize() {
        let largeImage = makeTestImage(width: 4000, height: 3000)
        let compressed = ImageCompressor.compressForInference(largeImage)
        
        #expect(compressed != nil)
        #expect(compressed!.count > 0)
        
        // Verify the resulting image fits within maxSize
        let result = UIImage(data: compressed!)
        #expect(result != nil)
        #expect(result!.size.width <= 1024)
        #expect(result!.size.height <= 1024)
    }
    
    @Test("Compress for inference does not upscale small images")
    func compressForInferenceNoUpscale() {
        let smallImage = makeTestImage(width: 100, height: 100)
        let compressed = ImageCompressor.compressForInference(smallImage)
        
        #expect(compressed != nil)
        
        let result = UIImage(data: compressed!)
        #expect(result != nil)
        // Should stay at original size (no upscale)
        #expect(result!.size.width == 100)
        #expect(result!.size.height == 100)
    }
    
    @Test("Compress for inference handles square image at boundary")
    func compressForInferenceBoundaryImage() {
        let image = makeTestImage(width: 1024, height: 1024)
        let compressed = ImageCompressor.compressForInference(image)
        
        #expect(compressed != nil)
        let result = UIImage(data: compressed!)
        #expect(result != nil)
        #expect(result!.size.width <= 1024)
        #expect(result!.size.height <= 1024)
    }
    
    // MARK: - Thumbnail Compression Tests
    
    @Test("Compress for thumbnail produces small output")
    func compressForThumbnail() {
        let largeImage = makeTestImage(width: 2000, height: 2000)
        let thumbnail = ImageCompressor.compressForThumbnail(largeImage)
        
        #expect(thumbnail != nil)
        
        let result = UIImage(data: thumbnail!)
        #expect(result != nil)
        #expect(result!.size.width <= 200)
        #expect(result!.size.height <= 200)
    }
    
    @Test("Compress for thumbnail is smaller than inference")
    func thumbnailSmallerThanInference() {
        let largeImage = makeTestImage(width: 3000, height: 3000)
        let inferenceData = ImageCompressor.compressForInference(largeImage)
        let thumbnailData = ImageCompressor.compressForThumbnail(largeImage)
        
        #expect(inferenceData != nil)
        #expect(thumbnailData != nil)
        // Thumbnail should be smaller in file size
        #expect(thumbnailData!.count < inferenceData!.count)
    }
}
