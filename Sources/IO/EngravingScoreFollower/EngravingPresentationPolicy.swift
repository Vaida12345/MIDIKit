//
//  EngravingPresentationPolicy.swift
//  MIDIKit
//


/// Converts committed musical inference into a stable marker and sparse viewport commands.
/// Engraving geometry is intentionally absent from the alignment filter.
struct EngravingPresentationPolicy {
    private var displayGestureIndex: Int?
    private var viewportLineOffset: Int?

    mutating func reset() {
        displayGestureIndex = nil
        viewportLineOffset = nil
    }

    mutating func makeUpdate(
        from alignment: EngravingAlignmentResult,
        score: EngravingScoreFeatureIndex,
        visibleRange: ClosedRange<Double>? = nil
    ) -> EngravingScoreFollower.Update {
        let musicalIndex = alignment.gestureIndex
        let destinationIsVisible = score.isVisible(musicalIndex, in: visibleRange)
        let didReframe = alignment.movement == .jump && !destinationIsVisible
        if displayGestureIndex == nil {
            displayGestureIndex = musicalIndex
        } else {
            switch alignment.movement {
            case .jump:
                displayGestureIndex = musicalIndex
            case .continuous, .recovered:
                let oldDisplay = displayGestureIndex ?? musicalIndex
                let proposedLine = score.gestures[musicalIndex].lineOffset
                let oldLine = score.gestures[oldDisplay].lineOffset
                let stagedFromLine = max(oldLine, viewportLineOffset ?? oldLine)
                if alignment.state == .tracking {
                    if proposedLine <= stagedFromLine + 1 {
                        displayGestureIndex = max(oldDisplay, musicalIndex)
                    } else if let intermediate = score.lastGestureIndex(
                        onLine: stagedFromLine + 1,
                        atOrBefore: musicalIndex
                    ) {
                        // A legal musical repair can cross several short systems. Catch the
                        // presentation up one system per event instead of freezing the marker or
                        // manufacturing a discontinuous jump.
                        displayGestureIndex = max(oldDisplay, intermediate)
                    }
                }
            case .held, .replay:
                break
            }
        }

        let displayIndex = displayGestureIndex ?? musicalIndex
        let displayLine = score.gestures[displayIndex].lineOffset
        let viewport: EngravingScoreFollower.ViewportRecommendation

        if didReframe {
            viewportLineOffset = displayLine
            viewport = .jump(toLine: score.lines[displayLine].index)
        } else if alignment.state == .tracking,
                  let oldViewportLine = viewportLineOffset,
                  oldViewportLine < displayLine,
                  !lineIsVisible(
                    oldViewportLine + 1,
                    score: score,
                    visibleRange: visibleRange
                  ) {
            // A marker that is catching up can cross several short or rest-only systems. Reveal
            // exactly one intermediate system per event.
            let nextLine = oldViewportLine + 1
            viewportLineOffset = nextLine
            viewport = .advance(toLine: score.lines[nextLine].index)
        } else if alignment.state == .tracking,
                  score.gestures[musicalIndex].lineOffset > displayLine + 1,
                  let oldViewportLine = viewportLineOffset,
                  oldViewportLine < score.gestures[musicalIndex].lineOffset,
                  !lineIsVisible(
                    oldViewportLine + 1,
                    score: score,
                    visibleRange: visibleRange
                  ) {
            // There may be no attack on an intervening rest-only system, so the display marker
            // cannot be staged there. Advance the spatial frame independently while holding it.
            let nextLine = oldViewportLine + 1
            viewportLineOffset = nextLine
            viewport = .advance(toLine: score.lines[nextLine].index)
        } else if alignment.state == .tracking,
                  let nextLine = nextNeededLine(after: displayIndex, score: score),
                  nextLine == displayLine + 1,
                  !lineIsVisible(nextLine, score: score, visibleRange: visibleRange),
                  viewportLineOffset != nextLine {
            // Move one system while the performer is still at the last onset of the current
            // system. If the application reports that the next system is already usable, no
            // movement is requested.
            viewportLineOffset = nextLine
            viewport = .advance(toLine: score.lines[nextLine].index)
        } else if alignment.state == .tracking,
                  alignment.movement == .continuous,
                  visibleRange == nil,
                  let oldLine = viewportLineOffset,
                  displayLine == oldLine + 1 {
            viewportLineOffset = displayLine
            viewport = .advance(toLine: score.lines[displayLine].index)
        } else {
            if viewportLineOffset == nil { viewportLineOffset = displayLine }
            viewport = .unchanged
        }

        let musicalGesture = score.gestures[musicalIndex]
        let displayGesture = score.gestures[displayIndex]
        return EngravingScoreFollower.Update(
            beat: musicalGesture.beat,
            displayBeat: displayGesture.beat,
            measureIndex: score.measures[musicalGesture.measureOffset].index,
            confidence: alignment.confidence,
            state: alignment.state,
            activeHands: alignment.activeHands,
            viewport: viewport,
            didReframe: didReframe
        )
    }

    private func nextNeededLine(
        after gestureIndex: Int,
        score: EngravingScoreFeatureIndex
    ) -> Int? {
        let currentLine = score.gestures[gestureIndex].lineOffset
        let index = gestureIndex + 1
        guard score.gestures.indices.contains(index) else { return nil }
        let line = score.gestures[index].lineOffset
        // A later onset on this line means movement is not needed yet.
        return line == currentLine ? nil : line
    }

    private func lineIsVisible(
        _ lineOffset: Int,
        score: EngravingScoreFeatureIndex,
        visibleRange: ClosedRange<Double>?
    ) -> Bool {
        guard let visibleRange else { return false }
        let line = score.lines[lineOffset]
        let point = visibleRange.upperBound - visibleRange.lowerBound
            <= EngravingReference.beatEpsilon
        if point { return line.beatRange.contains(visibleRange.lowerBound) }
        return max(line.beatRange.lowerBound, visibleRange.lowerBound)
            < min(line.beatRange.upperBound, visibleRange.upperBound)
                - EngravingReference.beatEpsilon
    }
}
