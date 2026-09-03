//
//  EngravingScoreFollower.swift
//  MIDIKit
//
//  Created by Vaida on 2026-09-03.
//

import CoreMIDI
import Foundation


/// A gesture-level score follower for an engraving-driven piano-practice interface.
///
/// The follower separates musical inference from presentation. `beat` reports the committed
/// musical location, while `displayBeat` and `viewport` preserve the performer's spatial frame
/// during mistakes, provisional corrections, and visible backward practice.
///
/// Begin an epoch with ``reset()``, publish ``visibleRange`` whenever the scroll view changes,
/// then pass events from ``MIDIInputController`` to ``consume(_:)``. The latest range received
/// after reset is used only as an acquisition prior. During performance it defines whether a
/// confirmed backward destination is a visible replay or a viewport-changing jump.
public final class EngravingScoreFollower {

    public enum HandParticipation: UInt8, Sendable, Hashable {
        case unknown
        case left
        case right
        case both
    }

    public enum TrackingState: UInt8, Sendable, Hashable {
        case acquiring
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
        /// The committed musical location. This may move backward for confirmed visible replay.
        public let beat: Double

        /// The stable marker location. It increases monotonically except on a confirmed jump.
        public let displayBeat: Double

        /// A compact local uncertainty interval. Distant internal alternatives are not folded
        /// into this range because doing so would imply every intervening beat is plausible.
        public let plausibleBeatRange: ClosedRange<Double>

        public let measureIndex: Int
        public let confidence: Double
        public let state: TrackingState
        public let activeHands: HandParticipation
        public let viewport: ViewportRecommendation

        /// `true` only when presentation should reframe discontinuously.
        public let didRelocate: Bool
    }

    public private(set) var reference: EngravingReference?

    /// The beat range currently visible in the engraving scroll view.
    public var visibleRange: ClosedRange<Double>? {
        didSet {
            let validated = Self.validRange(visibleRange)
            if !hasPerformanceStarted { pendingAcquisitionRange = validated }
            alignment?.setVisibleRange(validated)
        }
    }

    public private(set) var lastUpdate: Update?

    private var score: EngravingScoreFeatureIndex?
    private var assembler = PerformanceGestureAssembler()
    private var alignment: EngravingAlignmentModel?
    private var presentation = EngravingPresentationPolicy()
    private var pendingAcquisitionRange: ClosedRange<Double>?
    private var hasPerformanceStarted = false

    public init() {}

    /// Atomically replaces both musical and layout data, precomputes its lookup indices, and
    /// begins a fresh acquisition epoch.
    public func update(reference: EngravingReference) async {
        let compiled = EngravingScoreFeatureIndex(reference)
        self.reference = reference
        score = compiled
        alignment = EngravingAlignmentModel(score: compiled)
        reset()
    }

    /// Clears all performance evidence. Publish the viewport after this call; the last range
    /// received before the first note becomes the acquisition hint.
    public func reset() {
        pendingAcquisitionRange = nil
        hasPerformanceStarted = false
        assembler.reset()
        alignment?.reset(acquisitionRange: nil)
        alignment?.setVisibleRange(Self.validRange(visibleRange))
        presentation.reset()
        lastUpdate = nil
    }

    /// Consumes one event from ``MIDIInputController``.
    public func consume(_ input: MIDIInputEvent) -> Update? {
        consume(input.event, timestamp: input.timestamp)
    }

    /// Consumes an already-decoded MIDI event with its original input timestamp.
    ///
    /// Use this overload for alternate MIDI transports and deterministic trace playback. A zero
    /// timestamp explicitly means that timing is unavailable; pitch-based following continues.
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
        guard pitch < 128, velocity != 0, let score else {
            if velocity == 0 { consume(noteOff: pitch) }
            return nil
        }
        guard var alignment else { return nil }

        let isStarting = !hasPerformanceStarted
        if isStarting {
            alignment.reset(acquisitionRange: pendingAcquisitionRange)
            alignment.setVisibleRange(Self.validRange(visibleRange))
            hasPerformanceStarted = true
        }

        let change = assembler.noteOn(
            pitch: pitch,
            velocity: velocity,
            timestamp: timestamp,
            context: alignment.gestureContext
        )
        let aligned = alignment.consume(change)
        if isStarting, aligned == nil {
            // An out-of-reference note is not an informative start and must not latch either
            // the viewport sample or a spurious one-note gesture.
            assembler.reset()
            alignment.reset(acquisitionRange: pendingAcquisitionRange)
            alignment.setVisibleRange(Self.validRange(visibleRange))
            hasPerformanceStarted = false
        }
        self.alignment = alignment
        guard let aligned else { return nil }

        let update = presentation.makeUpdate(from: aligned, score: score)
        assertPresentationInvariants(previous: lastUpdate, current: update)
        lastUpdate = update
        return update
    }

    /// Records key release as gesture-boundary evidence without creating a score attack.
    func consume(noteOff pitch: UInt8, timestamp: MIDITimeStamp = 0) {
        guard pitch < 128 else { return }
        assembler.noteOff(pitch: pitch, timestamp: timestamp)
    }

    /// Records sustain and sostenuto state used by the gesture assembler.
    func consume(controlChange control: UInt8, value: UInt8) {
        assembler.controlChange(control: control, value: value)
    }

    private func assertPresentationInvariants(previous: Update?, current: Update) {
        if let previous, current.displayBeat < previous.displayBeat {
            assert(current.didRelocate)
        }
        switch current.viewport {
        case .unchanged:
            break
        case .advance:
            assert(!current.didRelocate)
        case .jump:
            assert(current.didRelocate)
        }
    }

    private static func validRange(
        _ range: ClosedRange<Double>?
    ) -> ClosedRange<Double>? {
        guard let range, range.lowerBound.isFinite, range.upperBound.isFinite else { return nil }
        return range
    }
}
