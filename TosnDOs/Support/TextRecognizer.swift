import Foundation
import Vision
import ImageIO
import CoreGraphics

/// Vision OCR, on device. Lines carry normalised boxes for `CaptureParser`.
enum TextRecognizer {
    static func lines(from data: Data) async -> [RecognizedLine] {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Chinese first, English as fallback: mixed screenshots carry both.
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                    let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                    let lines: [RecognizedLine] = observations.compactMap { observation in
                        guard let candidate = observation.topCandidates(1).first else { return nil }
                        let box = observation.boundingBox
                        return RecognizedLine(
                            text: candidate.string,
                            minX: box.minX,
                            maxX: box.maxX,
                            midY: box.midY,
                            height: box.height
                        )
                    }
                    continuation.resume(returning: lines)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }
}
