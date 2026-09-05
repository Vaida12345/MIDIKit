import Foundation

/// All viewport state is based on caller feedback. Requested geometry is never observed geometry.
struct EngravingPresentation {
    typealias Action = EngravingScoreFollower.ViewportRecommendation
    struct Handoff {
        var episode: UInt64
        var precedingLine: Int
        var targetLine: Int
    }
    struct Intent {
        var action: Action
        var targetLine: Int
        var episode: UInt64
        var offset: Int
        var anchor: Double
        var visibilityGeneration: UInt64
    }
    private(set) var revision: UInt64 = 0
    private(set) var pending: Intent?
    private(set) var handoff: Handoff?
    private(set) var displayBeat: Double?
    private(set) var visibility: ClosedRange<Double>?
    private var visibilityGeneration: UInt64 = 0
    private var previousOffset: Int?
    private var previousEpisode: UInt64?
    private var enteredLine: Int?
    private var achieved: Intent?
    private var refused: Intent?
    private var feedback = false
    private var lastJumpObservation: UInt64 = 0
    private var postJumpOnsets = 0
    private var lastCountedObservation: UInt64 = 0
    private var acknowledgedOmissionStart: Int?

    mutating func report(_ range: ClosedRange<Double>?, score: EngravingScoreIndex) {
        let usable = score.usable(range)
        if visibility != usable { visibilityGeneration &+= 1 }
        visibility = usable
        feedback = true // Even an unchanged report can acknowledge refusal.
    }

    private func readable(_ line: Int, score: EngravingScoreIndex) -> Bool {
        guard let visibility else { return false }
        let extent = score.lines[line].extent
        return visibility.lowerBound <= extent.lowerBound && visibility.upperBound >= extent.upperBound
    }

    private func anchor(_ path: EngravingPath, score: EngravingScoreIndex) -> Double {
        guard path.hands == .both, path.leftAssignments >= 2, path.rightAssignments >= 2,
              let previous = path.previous else { return score.moments[path.current.offset].beat }
        let moment = score.moments[previous.offset]
        // Already attacked sustains do not hold the reading anchor behind the frontier.
        let missing = moment.pitches & ~previous.pitches
        return missing == 0 ? score.moments[path.current.offset].beat : moment.beat
    }

    private func anchorsVisible(_ path: EngravingPath, score: EngravingScoreIndex) -> Bool {
        guard let visibility else { return false }
        return score.contains(score.moments[path.current.offset].beat, in: visibility)
            && score.contains(anchor(path, score: score), in: visibility)
    }

    private mutating func cancel() {
        guard pending != nil else { return }
        pending = nil
        revision &+= 1
    }

    mutating func consume(path: EngravingPath, evidence: EngravingEvidence,
                          state: EngravingScoreFollower.TrackingState, fresh: Bool,
                          score: EngravingScoreIndex) -> Action {
        let offset = path.current.offset
        let beat = score.moments[offset].beat
        let line = score.moments[offset].line
        let newEpisode = previousEpisode != nil && previousEpisode != path.episode
        let backward = previousOffset.map { offset < $0 } ?? false
        if newEpisode || backward {
            handoff = nil
            enteredLine = nil
            achieved = nil
            refused = nil
            acknowledgedOmissionStart = nil
            cancel()
        }
        if displayBeat == nil { displayBeat = beat }
        if state == .tracking { displayBeat = max(displayBeat ?? beat, beat) }

        if let old = previousOffset, previousEpisode == path.episode, offset > old {
            let preceding = score.moments[old].line
            if line > preceding {
                // Preserve the preceding confirmed line while confidence is still developing.
                if handoff == nil { handoff = Handoff(episode: path.episode, precedingLine: preceding, targetLine: line) }
                else { handoff?.targetLine = line }
                enteredLine = line
            }
        }
        previousOffset = offset
        previousEpisode = path.episode

        if state != .tracking { cancel(); feedback = false; return .unchanged }
        if lastJumpObservation != 0, fresh, path.advanced, path.lastObservation > lastCountedObservation {
            postJumpOnsets = min(2, postJumpOnsets + 1)
            lastCountedObservation = path.lastObservation
        }

        if feedback {
            if let request = pending {
                if readable(request.targetLine, score: score) || anchorsVisible(path, score: score) {
                    achieved = Intent(action: request.action, targetLine: line, episode: path.episode,
                        offset: offset, anchor: anchor(path, score: score), visibilityGeneration: visibilityGeneration)
                    acknowledgedOmissionStart = path.omissionStart
                    if readable(line, score: score) { handoff = nil }
                    cancel()
                } else {
                    refused = request
                    refused?.visibilityGeneration = visibilityGeneration
                    cancel()
                }
            }
            feedback = false
        }

        guard let visibility, fresh else { return .unchanged }
        if readable(line, score: score) {
            enteredLine = line
            acknowledgedOmissionStart = path.omissionStart
            if pending?.targetLine == line { cancel() }
            handoff = nil
            return .unchanged
        }
        if let achieved, achieved.episode == path.episode,
           achieved.visibilityGeneration == visibilityGeneration, anchorsVisible(path, score: score) {
            return .unchanged
        }
        if let refused, refused.episode == path.episode, refused.offset == offset,
           refused.visibilityGeneration == visibilityGeneration { return .unchanged }

        let safeAnchor = anchor(path, score: score)
        func residualAgrees(_ residual: EngravingResidual, jump: Bool) -> Bool {
            residual.episode == path.episode && residual.coherent && residual.fresh
                && score.moments[residual.range.lowerBound].line == line
                && score.moments[residual.range.upperBound].line == line
                && !score.hasChords(in: max(0, residual.range.lowerBound - 16)...residual.range.upperBound)
                && (!jump || residual.onsets >= 2 && residual.separation >= log(4))
        }
        let actionSupport = evidence.support(where: {
            $0.episode == path.episode && score.moments[$0.current.offset].line == line && $0.matched
                && self.anchor($0, score: score) >= score.lines[line].extent.lowerBound
        }, compatibleResidual: { residualAgrees($0, jump: false) })
        let ordinary: Bool
        let largeUnreadOmission: Bool
        if path.omittedAttacks >= 4, let start = path.omissionStart, start != acknowledgedOmissionStart {
            largeUnreadOmission = !score.contains(score.moments[start].beat, in: visibility)
        } else { largeUnreadOmission = false }
        if let handoff {
            ordinary = handoff.episode == path.episode && handoff.targetLine == line && line == handoff.precedingLine + 1
        } else {
            ordinary = enteredLine == line && !newEpisode && !backward
        }
        if ordinary && !largeUnreadOmission && actionSupport >= 0.98 && safeAnchor >= score.lines[line].extent.lowerBound {
            guard pending == nil else { return .unchanged }
            return issue(.advance(toLine: score.lines[line].id), path: path, anchor: safeAnchor, score: score)
        }

        // Initial offscreen acquisition, new episodes, large omissions, and multi-line
        // continuity all pass the same stronger visual gate.
        if !ordinary, anchorsVisible(path, score: score) {
            let next = offset + 1
            if next >= score.moments.count || score.contains(score.moments[next].beat, in: visibility) { return .unchanged }
        }
        guard !anchorsVisible(path, score: score) || !ordinary else { return .unchanged }
        let occurrenceSupport = evidence.mode(path)
        let destinationSupport = evidence.exact(offset)
        let attackFreeTraversal: Bool
        if let handoff, line > handoff.precedingLine + 1, !path.skippedAttacks {
            attackFreeTraversal = path.onsets >= 2
        } else { attackFreeTraversal = false }
        let corroborated = path.onsets >= 2 && path.onsetEvidence >= log(4)
            && (!path.skippedAttacks || path.recoveryOnsets >= 2)
        let jumpSupport = evidence.support(where: {
            $0.episode == path.episode && score.moments[$0.current.offset].line == line && $0.matched
                && self.anchor($0, score: score) >= score.lines[line].extent.lowerBound
                && (attackFreeTraversal || $0.onsets >= 2 && $0.onsetEvidence >= log(4))
        }, compatibleResidual: { residualAgrees($0, jump: true) })
        guard occurrenceSupport >= 0.995, jumpSupport >= 0.995, destinationSupport >= 0.95,
              corroborated || attackFreeTraversal else { return .unchanged }
        let continuous = evidence.support { $0.episode != path.episode }
        guard continuous == 0 || occurrenceSupport / continuous >= 100 else { return .unchanged }
        if lastJumpObservation != 0 {
            guard path.lastObservation > lastJumpObservation else { return .unchanged }
            if postJumpOnsets < 2 {
                if path.episode <= lastJumpObservation { return .unchanged }
                guard occurrenceSupport / max(1e-15, 1 - occurrenceSupport) >= 398 else { return .unchanged }
            }
        }
        // A pending jump is not repeatedly reissued, even if the host does not respond.
        if let pending, case .jump = pending.action { return .unchanged }
        displayBeat = beat
        lastJumpObservation = path.lastObservation
        postJumpOnsets = 0
        lastCountedObservation = path.lastObservation
        return issue(.jump(toLine: score.lines[line].id), path: path, anchor: safeAnchor, score: score)
    }

    private mutating func issue(_ action: Action, path: EngravingPath, anchor: Double, score: EngravingScoreIndex) -> Action {
        revision &+= 1
        pending = Intent(action: action, targetLine: score.moments[path.current.offset].line,
                         episode: path.episode, offset: path.current.offset, anchor: anchor,
                         visibilityGeneration: visibilityGeneration)
        refused = nil
        feedback = false
        return action
    }
}
