//
//  EngravingPresentationPolicy.swift
//  MIDIKit
//


/// Converts musical alignment into a perceptually stable marker and rare viewport command.
/// The policy is intentionally ignorant of MIDI evidence; uncertain inference cannot leak into
/// scrolling through a score weight or candidate ranking change.
struct EngravingPresentationPolicy {
    private var displayGestureIndex: Int?
    private var viewportLineOffset: Int?

    mutating func reset() {
        displayGestureIndex = nil
        viewportLineOffset = nil
    }

    mutating func makeUpdate(
        from alignment: EngravingAlignmentResult,
        score: EngravingScoreFeatureIndex
    ) -> EngravingScoreFollower.Update {
        let musicalIndex = alignment.gestureIndex
        var didRelocate = alignment.movement == .jump

        if displayGestureIndex == nil {
            displayGestureIndex = musicalIndex
        } else {
            switch alignment.movement {
            case .jump:
                displayGestureIndex = musicalIndex
            case .continuous:
                if alignment.state == .tracking {
                    displayGestureIndex = max(displayGestureIndex ?? musicalIndex, musicalIndex)
                }
            case .held, .correction, .replay:
                break
            }
        }

        var displayIndex = displayGestureIndex ?? musicalIndex
        let displayLine = score.gestures[displayIndex].lineOffset
        let viewport: EngravingScoreFollower.ViewportRecommendation

        if didRelocate {
            viewportLineOffset = displayLine
            viewport = .jump(toLine: score.lines[displayLine].index)
        } else if alignment.state == .tracking,
                  alignment.movement == .continuous,
                  let oldLine = viewportLineOffset,
                  displayLine == oldLine + 1 {
            viewportLineOffset = displayLine
            viewport = .advance(toLine: score.lines[displayLine].index)
        } else if alignment.state == .tracking,
                  alignment.movement == .continuous,
                  let oldLine = viewportLineOffset,
                  displayLine > oldLine + 1 {
            // Crossing more than one line is visually discontinuous even when the alignment
            // path describes it as a forward score deletion.
            didRelocate = true
            displayGestureIndex = musicalIndex
            displayIndex = musicalIndex
            let destinationLine = score.gestures[musicalIndex].lineOffset
            viewportLineOffset = destinationLine
            viewport = .jump(toLine: score.lines[destinationLine].index)
        } else {
            if viewportLineOffset == nil { viewportLineOffset = displayLine }
            viewport = .unchanged
        }

        let musicalMeasure = score.gestures[musicalIndex].measureOffset
        let plausibleBeats: [Double] = alignment.plausibleIndices.compactMap { index -> Double? in
            guard score.gestures.indices.contains(index),
                  abs(score.gestures[index].measureOffset - musicalMeasure) <= 1 else {
                return nil
            }
            return score.gestures[index].beat
        }
        let musicalGesture = score.gestures[musicalIndex]
        let displayGesture = score.gestures[displayIndex]
        let lower = plausibleBeats.min() ?? musicalGesture.beat
        let upper = plausibleBeats.max() ?? musicalGesture.beat

        return EngravingScoreFollower.Update(
            beat: musicalGesture.beat,
            displayBeat: displayGesture.beat,
            plausibleBeatRange: lower...upper,
            measureIndex: score.measures[musicalGesture.measureOffset].index,
            confidence: alignment.confidence,
            state: alignment.state,
            activeHands: alignment.activeHands,
            viewport: viewport,
            didRelocate: didRelocate
        )
    }
}
