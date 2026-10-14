import UIKit
import Vision
import ImageIO

/// Reads receipt text on the device with Apple's Vision framework.
enum TextRecognizer {
    /// Returns the text as receipt lines: pieces at the same height are joined left to right,
    /// so an item name and its price end up on one line.
    static func text(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { return "" }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                request.recognitionLanguages = ["en-US"]
                do {
                    try VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])
                    continuation.resume(returning: rows(from: request.results ?? []))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private struct Piece { let text: String; let midY: CGFloat; let minX: CGFloat; let height: CGFloat }

    private static func rows(from observations: [VNRecognizedTextObservation]) -> String {
        let pieces = observations.compactMap { o -> Piece? in
            guard let text = o.topCandidates(1).first?.string else { return nil }
            let b = o.boundingBox
            return Piece(text: text, midY: b.midY, minX: b.minX, height: b.height)
        }.sorted { $0.midY > $1.midY }
        var rows: [[Piece]] = []
        for piece in pieces {
            if let first = rows.last?.first, abs(first.midY - piece.midY) < max(first.height, piece.height) * 0.55 {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }
        return rows.map { $0.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: "   ") }.joined(separator: "\n")
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
