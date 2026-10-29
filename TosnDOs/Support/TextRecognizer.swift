import Foundation
import Vision
import ImageIO
import CoreGraphics

/// 本机 OCR：Vision 的文本识别，不联网、不上传、不申请权限。
/// 返回的每一行都带着归一化坐标，交给 `CaptureParser` 去拼行、找时间地点。
enum TextRecognizer {
    static func lines(from data: Data) async -> [RecognizedLine] {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // 简体中文为主，英文兜底——混排的截图里常夹着英文单词。
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
