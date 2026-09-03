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

        /// Stable primary marker. It never decreases without `didReframe`.
        public let displayBeat: Double

        public let measureIndex: Int
        public let confidence: Double
        public let state: TrackingState
        public let activeHands: HandParticipation
        public let viewport: ViewportRecommendation

        /// True only when the application should change the performer's spatial frame.
        public let didReframe: Bool
    }

    public private(set) var reference: EngravingReference?

    /// The beat range actually usable in the current engraving viewport.
    ///
    /// Before the first attack after `userReset()`, this is a defeasible acquisition prior.
    /// During tracking it affects presentation and visible-replay classification, never ordinary
    /// musical continuity.
    public var visibleRange: ClosedRange<Double>? {
        didSet {
            let range = Self.validRange(visibleRange)
            if !hasPerformanceStarted { pendingAcquisitionRange = range }
            alignment?.setVisibleRange(range)
        }
    }

    public private(set) var lastUpdate: Update?

    private var score: EngravingScoreFeatureIndex?
    private var inputState = PerformanceInputState()
    private var alignment: EngravingAlignmentModel?
    private var presentation = EngravingPresentationPolicy()
    private var pendingAcquisitionRange: ClosedRange<Double>?
    private var hasPerformanceStarted = false

    public init() {}

    /// Atomically replaces music and layout, recompiles immutable features, and hard-resets all
    /// positional and performer-specific evidence.
    public func update(reference: EngravingReference) async {
        let compiled = EngravingScoreFeatureIndex(reference)
        self.reference = reference
        score = compiled
        var model = EngravingAlignmentModel(score: compiled)
        model.hardReset(acquisitionRange: Self.validRange(visibleRange))
        alignment = model
        inputState.reset()
        presentation.reset()
        pendingAcquisitionRange = Self.validRange(visibleRange)
        hasPerformanceStarted = false
        lastUpdate = nil
    }

    /// Signals the beginning of user navigation. This is the sole public reset/navigation API.
    /// It clears position and partial-onset evidence, retains learned performer calibration, and
    /// detaches timing across the interaction. Publish the new `visibleRange` while scrolling;
    /// the last range received before the next attack becomes the acquisition hint.
    public func userReset() {
        pendingAcquisitionRange = nil
        hasPerformanceStarted = false
        inputState.reset()
        alignment?.userReset(acquisitionRange: nil)
        alignment?.setVisibleRange(Self.validRange(visibleRange))
        presentation.reset()
        lastUpdate = nil
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
        switch event {
        case let .noteOn(pitch, velocity):
            return consume(noteOn: pitch, velocity: velocity, timestamp: timestamp)
        case let .noteOff(pitch):
            consume(noteOff: pitch, timestamp: timestamp)
            return nil
        case let .controlChange(control, value):
            consume(controlChange: control, value: value)
            return nil
        }
    }

    /// Deterministic decoded-note entry point used by trace playback and package tests.
    func consume(
        noteOn pitch: UInt8,
        velocity: UInt8 = 127,
        timestamp: MIDITimeStamp
    ) -> Update? {
        guard pitch < 128 else { return nil }
        if velocity == 0 {
            consume(noteOff: pitch, timestamp: timestamp)
            return nil
        }
        guard let score, var alignment else { return nil }

        let isStarting = !hasPerformanceStarted
        if isStarting {
            alignment.userReset(acquisitionRange: pendingAcquisitionRange)
            alignment.setVisibleRange(Self.validRange(visibleRange))
            hasPerformanceStarted = true
        }

        let attack = inputState.noteOn(
            pitch: pitch,
            velocity: velocity,
            timestamp: timestamp
        )
        let aligned = alignment.consume(attack)
        if isStarting, aligned == nil, !alignment.hasAcquisitionEvidence {
            // A pitch absent from the score is not allowed to latch a false epoch.
            inputState.reset()
            alignment.userReset(acquisitionRange: pendingAcquisitionRange)
            alignment.setVisibleRange(Self.validRange(visibleRange))
            hasPerformanceStarted = false
        }
        self.alignment = alignment
        guard let aligned else { return nil }

        let update = presentation.makeUpdate(
            from: aligned,
            score: score,
            visibleRange: Self.validRange(visibleRange)
        )
        assertPresentationInvariants(previous: lastUpdate, current: update)
        lastUpdate = update
        return update
    }

    /// Records physical key release and note dwell without creating a score attack.
    func consume(noteOff pitch: UInt8, timestamp: MIDITimeStamp = 0) {
        guard pitch < 128 else { return }
        let release = inputState.noteOff(pitch: pitch, timestamp: timestamp)
        alignment?.consume(release)
    }

    /// Records sustain and sostenuto controller state. Pedals affect physical state, not score
    /// onset boundaries directly.
    func consume(controlChange control: UInt8, value: UInt8) {
        inputState.controlChange(control: control, value: value)
    }

    private func assertPresentationInvariants(previous: Update?, current: Update) {
        if let previous, current.displayBeat < previous.displayBeat {
            assert(current.didReframe)
        }
        switch current.viewport {
        case .unchanged:
            break
        case .advance:
            assert(!current.didReframe)
        case .jump:
            assert(current.didReframe)
        }
    }

    private static func validRange(
        _ range: ClosedRange<Double>?
    ) -> ClosedRange<Double>? {
        guard let range, range.lowerBound.isFinite, range.upperBound.isFinite else { return nil }
        return range
    }
}
