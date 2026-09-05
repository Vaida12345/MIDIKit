//
//  EngravingScoreFollower.swift
//  MIDIKit
//

import CoreMIDI
import Foundation


/// Real-time score following for an engraving-driven piano-practice interface.
///
/// `beat` is the committed musical location. `displayBeat` and `viewport` are governed by a
/// separate presentation policy so uncertainty, ordinary mistakes, and visible replay do not
/// destabilize the performer's spatial frame.
public final class EngravingScoreFollower {
    public enum HandParticipation: UInt8, Sendable, Hashable {
        case unknown
        case left
        case right
        case both
    }

    /// Public tracking quality. Acquisition is intentionally private: before the first reliable
    /// commitment, `consume` returns `nil` rather than publishing a misleading state.
    public enum TrackingState: UInt8, Sendable, Hashable {
        case tracking
        case uncertain
        case lost
    }

    public enum ViewportRecommendation: Sendable, Hashable {
        case unchanged
        case advance(toLine: Int)
        case jump(toLine: Int)
    }

    public struct Update: Sendable, Hashable {
        /// Committed musical location. It can decrease only for confirmed replay or reframing.
        public let beat: Double

        /// Stable decorative marker. It never decreases without `didReframe`.
        public let displayBeat: Double

        public let measureIndex: Int
        public let confidence: Double
        public let state: TrackingState
        public let activeHands: HandParticipation
        public let viewport: ViewportRecommendation

        /// Epoch-local authority. A newer unchanged update cancels older deferred requests.
        public let viewportRevision: UInt64

        /// True only when the application should change the performer's spatial frame.
        public let didReframe: Bool
    }

    public private(set) var reference: EngravingReference?

    /// The beat range actually usable in the current engraving viewport.
    public var visibleRange: ClosedRange<Double>? {
        didSet {
            guard let score else { return }
            presentation.report(visibleRange, score: score)
            filter.refreshHint(visibleRange, score: score)
        }
    }

    private var score: EngravingScoreIndex?
    private var input = EngravingInputState()
    private var calibration = EngravingCalibration()
    private var filter = EngravingFilter()
    private var presentation = EngravingPresentation()
    private var committed: EngravingPath?
    private var lastUpdate: Update?
    private var trackingState: TrackingState = .uncertain
    private var hands: HandParticipation = .unknown

    public init() {}

    /// Atomically replaces music and layout, recompiles immutable features, and hard-resets all
    /// positional and performer-specific evidence.
    public func update(reference: EngravingReference) async {
        let compiled = EngravingScoreIndex(reference)
        self.reference = reference
        score = compiled
        reset()
    }

    /// Begins a navigation epoch, retaining only broad calibration and provisional visibility.
    /// The caller clears its marker and queued requests. This does not identify when a drag ends;
    /// manual-scroll interval signaling remains an integration concern.
    public func userReset() {
        clearState(retainingCalibration: true)
    }

    /// Clears all mutable state, including visibility, while retaining the installed score.
    /// The caller clears its marker and queued viewport requests immediately.
    public func reset() {
        clearState(retainingCalibration: false)
    }

    private func clearState(retainingCalibration: Bool) {
        input = EngravingInputState()
        filter = EngravingFilter()
        presentation = EngravingPresentation()
        committed = nil
        lastUpdate = nil
        trackingState = .uncertain
        hands = .unknown
        if !retainingCalibration {
            calibration = EngravingCalibration()
            visibleRange = nil
        }
        if let score {
            presentation.report(visibleRange, score: score)
            filter.refreshHint(visibleRange, score: score)
        }
    }

    public func consume(_ input: MIDIInputEvent) -> Update? {
        consume(input.event, timestamp: input.timestamp)
    }

    /// Consumes a decoded MIDI event with its original host-time timestamp. Zero means timing is
    /// unavailable; event order and pitch-driven inference continue normally.
    public func consume(
        _ event: ParsedInputEvent,
        timestamp: MIDITimeStamp
    ) -> Update? {
        guard let score else { return nil }
        let observation = input.consume(event, timestamp: timestamp)
        _ = filter.consume(observation, score: score, calibration: calibration, lost: trackingState == .lost)
        if observation.attack != nil { filter.refineAcquisition(score: score, calibration: calibration) }
        let evidence = filter.evidence()
        guard let best = evidence.best else { return publishHeld(evidence: evidence, observation: observation, score: score) }
        let exact = evidence.exact(best.current.offset)
        let mode = committed == nil
            ? evidence.acquisitionMode(best)
            : evidence.mode(best)
        let fresh = observation.attack != nil && best.matched
        let resolving = observation.attack == nil && observation.changed && observation.released != nil
        let coherent = (best.fit >= 0.55 || best.matched && best.advanced && exact >= 0.98)
            && mode >= 0.90 && evidence.noiseSupport < 0.20
        if committed == nil {
            guard (fresh || resolving), exact >= 0.80, coherent else { return nil }
            committed = best
            filter.acquire(best)
            trackingState = .tracking
        } else if let old = committed {
            let continuous = old.episode == best.episode && best.current.offset >= old.current.offset
            // The change point is latent. Several change-point ages can agree on the same
            // new occurrence; demand corroboration within each path before marginalizing.
            let relocation = evidence.support(where: {
                $0.episode != old.episode && $0.current.offset == best.current.offset
                    && $0.onsets >= 2 && $0.onsetEvidence >= log(4) && $0.fit >= 0.55
            }, compatibleResidual: {
                $0.episode != old.episode && $0.range == best.current.offset...best.current.offset
                    && $0.coherent && $0.onsets >= 2 && $0.separation >= log(4)
            })
            if continuous && exact >= 0.80 && coherent && (fresh || resolving) {
                committed = best
                trackingState = .tracking
            } else if !continuous && relocation >= 0.95,
                      best.onsets >= 2, best.onsetEvidence >= log(4), fresh || resolving {
                filter.acquire(best, preservingEpisode: old.episode)
                committed = best
                trackingState = .tracking
            } else {
                let incumbentSupport = evidence.support { $0.episode == old.episode && abs($0.current.offset - old.current.offset) <= 2 }
                let incumbentFit = evidence.paths.first { $0.path.episode == old.episode }?.path.fit ?? 0
                if incumbentSupport < 0.20 || evidence.noiseSupport > 0.80 || incumbentFit < 0.20 { trackingState = .lost }
                else if incumbentSupport < 0.70 || incumbentFit < 0.55 || !continuous { trackingState = .uncertain }
                if let held = evidence.paths.first(where: { $0.path.episode == old.episode && $0.path.current.offset == old.current.offset }) {
                    committed = held.path
                }
            }
        }
        guard let committed else { return nil }
        filter.committedEpisode = committed.episode
        filter.committedOffset = committed.current.offset
        updateHands(evidence, path: committed)
        if trackingState == .tracking && fresh && committed.episode == best.episode,
           committed.onsets >= 3, exact >= 0.98, !best.advanced,
           let spread = EngravingHostTime.seconds(from: best.trailing ? best.previous?.firstTime ?? 0 : best.current.firstTime, to: timestamp) {
            if best.trailing { calibration.observeHandOffset(spread) }
            else { calibration.observe(spread: spread, rolled: score.moments[best.current.offset].rolled) }
        }
        let action = presentation.consume(path: committed, evidence: filter.evidence(), state: trackingState,
                                          fresh: fresh || resolving, score: score)
        return publish(path: committed, evidence: evidence, action: action, score: score)
    }

    private func updateHands(_ evidence: EngravingEvidence, path: EngravingPath) {
        guard trackingState == .tracking, path.onsets >= 3 else { hands = .unknown; return }
        let left = evidence.support { $0.hands == .left && $0.leftAssignments >= 3 }
        let right = evidence.support { $0.hands == .right && $0.rightAssignments >= 3 }
        let both = evidence.support { $0.hands == .both && $0.leftAssignments >= 2 && $0.rightAssignments >= 2 }
        if left >= 0.85 { hands = .left }
        else if right >= 0.85 { hands = .right }
        else if both >= 0.85 { hands = .both }
        else {
            let support: Double = hands == .left ? left : hands == .right ? right : hands == .both ? both : 0
            if support < 0.60 { hands = .unknown }
        }
    }

    private func publishHeld(evidence: EngravingEvidence, observation: EngravingInputState.Observation,
                             score: EngravingScoreIndex) -> Update? {
        guard let committed else { return nil }
        trackingState = .lost
        hands = .unknown
        let action = presentation.consume(path: committed, evidence: evidence, state: .lost, fresh: false, score: score)
        return publish(path: committed, evidence: evidence, action: action, score: score)
    }

    private func publish(path: EngravingPath, evidence: EngravingEvidence,
                         action: ViewportRecommendation, score: EngravingScoreIndex) -> Update? {
        let moment = score.moments[path.current.offset]
        let reframe: Bool
        if case .jump = action { reframe = true } else { reframe = false }
        let update = Update(beat: moment.beat, displayBeat: presentation.displayBeat ?? moment.beat,
                            measureIndex: moment.measure, confidence: evidence.exact(path.current.offset),
                            state: trackingState, activeHands: hands, viewport: action,
                            viewportRevision: presentation.revision, didReframe: reframe)
        if let last = lastUpdate, update.beat == last.beat, update.displayBeat == last.displayBeat,
           update.state == last.state, update.activeHands == last.activeHands,
           abs(update.confidence - last.confidence) < 0.05,
           update.viewportRevision == last.viewportRevision, action == .unchanged { return nil }
        lastUpdate = update
        return update
    }

    // Internal diagnostics are intentionally not a second public following API.
    var diagnostics: (paths: Int, residuals: Int, history: Int, expansions: Int, destinations: Int, calibration: Int) {
        (filter.paths.count, filter.residuals.count, filter.history.count, filter.expansions, filter.destinations, calibration.support)
    }
}
