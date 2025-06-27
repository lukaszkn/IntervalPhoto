//
//  SingleFrameOutput.swift
//  ImageDropToText
//
//  Created by Lukasz on 18/06/2025.
//

import Cocoa
import ScreenCaptureKit
import AVFoundation

class SingleFrameOutput: NSObject, SCStreamOutput {
    private var captured = false
    private let onCapture: (NSImage?) -> Void

    init(onCapture: @escaping (NSImage?) -> Void) {
        self.onCapture = onCapture
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard !captured,
              let pixelBuffer = sampleBuffer.imageBuffer else { return }

        captured = true

        // Convert CVPixelBuffer to CGImage
        var cgImage: CGImage?
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        cgImage = context.createCGImage(ciImage, from: ciImage.extent)

        // Convert to NSImage
        var nsImage: NSImage? = nil
        if let cgImage = cgImage {
            nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }

        onCapture(nsImage)
    }
}
