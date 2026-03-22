import Vision
import CoreGraphics

enum OCREngine {
    static func recognizeText(in image: CGImage, completion: @escaping (Result<String, Error>) -> Void) {
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation],
                  !observations.isEmpty else {
                completion(.success(""))
                return
            }

            let text = formatObservations(observations)
            completion(.success(text))
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: - Smart Formatting

    private static func formatObservations(_ observations: [VNRecognizedTextObservation]) -> String {
        // Extract text with bounding boxes
        // Vision bounding box: origin at bottom-left, normalized 0-1
        let lines: [(text: String, box: CGRect)] = observations.compactMap { obs in
            guard let candidate = obs.topCandidates(1).first else { return nil }
            return (candidate.string, obs.boundingBox)
        }

        guard !lines.isEmpty else { return "" }

        // Detect columns by clustering X positions
        let columns = detectColumns(lines)

        // Process each column top-to-bottom, then join columns
        var columnTexts: [String] = []

        for column in columns {
            // Sort top-to-bottom (higher Y = higher on screen in Vision coords)
            let sorted = column.sorted { $0.box.midY > $1.box.midY }
            let formatted = formatColumn(sorted)
            columnTexts.append(formatted)
        }

        return columnTexts.joined(separator: "\n\n")
    }

    private static func detectColumns(_ lines: [(text: String, box: CGRect)]) -> [[(text: String, box: CGRect)]] {
        guard lines.count > 1 else { return [lines] }

        // Cluster lines by horizontal center (midX)
        // Use a simple threshold: if midX values are far apart, it's a different column
        let sorted = lines.sorted { $0.box.midX < $1.box.midX }

        var columns: [[(text: String, box: CGRect)]] = [[sorted[0]]]
        let columnThreshold: CGFloat = 0.25 // 25% of image width

        for i in 1..<sorted.count {
            let currentMidX = sorted[i].box.midX
            let lastColumnMidX = columns[columns.count - 1]
                .map { $0.box.midX }
                .reduce(0, +) / CGFloat(columns[columns.count - 1].count)

            if abs(currentMidX - lastColumnMidX) > columnThreshold {
                columns.append([sorted[i]])
            } else {
                columns[columns.count - 1].append(sorted[i])
            }
        }

        // Sort columns left-to-right
        return columns.sorted { col1, col2 in
            let avg1 = col1.map { $0.box.midX }.reduce(0, +) / CGFloat(col1.count)
            let avg2 = col2.map { $0.box.midX }.reduce(0, +) / CGFloat(col2.count)
            return avg1 < avg2
        }
    }

    private static func formatColumn(_ lines: [(text: String, box: CGRect)]) -> String {
        guard !lines.isEmpty else { return "" }
        guard lines.count > 1 else { return lines[0].text }

        // Calculate average line height as a baseline for spacing
        let avgLineHeight = lines.map { $0.box.height }.reduce(0, +) / CGFloat(lines.count)

        // Measure all gaps between consecutive lines
        var gaps: [CGFloat] = []
        for i in 0..<lines.count - 1 {
            // Gap = bottom of current line minus top of next line (in Vision coords, higher Y = higher on screen)
            let gap = lines[i].box.minY - lines[i + 1].box.maxY
            gaps.append(max(gap, 0))
        }

        // Use multiple heuristics for paragraph detection:
        // 1. Gap > 1.3x median gap (relative to surrounding spacing)
        // 2. Gap > 0.5x average line height (absolute threshold)
        // Either condition triggers a paragraph break

        let medianGap: CGFloat
        if gaps.isEmpty {
            medianGap = avgLineHeight * 0.3
        } else {
            let sortedGaps = gaps.sorted()
            medianGap = sortedGaps[sortedGaps.count / 2]
        }

        let relativeThreshold = medianGap * 1.3
        let absoluteThreshold = avgLineHeight * 0.5

        var result = lines[0].text
        for i in 1..<lines.count {
            let gap = max(lines[i - 1].box.minY - lines[i].box.maxY, 0)

            let isParagraphBreak: Bool
            if gaps.count < 3 {
                // Too few lines to use relative spacing — use absolute threshold
                isParagraphBreak = gap > absoluteThreshold
            } else {
                isParagraphBreak = gap > relativeThreshold || gap > absoluteThreshold
            }

            // Also detect indentation changes as paragraph breaks
            let indentDiff = abs(lines[i].box.minX - lines[i - 1].box.minX)
            let hasIndentChange = indentDiff > 0.03 // 3% of image width

            if isParagraphBreak || hasIndentChange {
                result += "\n\n" + lines[i].text
            } else {
                result += "\n" + lines[i].text
            }
        }

        return result
    }
}
