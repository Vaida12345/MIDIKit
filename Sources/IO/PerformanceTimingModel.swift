//
//  PerformanceTimingModel.swift
//  MIDIKit
//

import CoreMIDI
import Foundation


/// A robust tempo clock belonging to one alignment path.
///
/// The estimate lives in Core MIDI host-time ticks per score beat, so no wall-clock conversion
/// occurs on the input path. Log-space updates make proportional tempo changes symmetric.
struct PerformanceTempoTracker {
    private(set) var logTicksPerBeat: Double?
    private(set) var logDeviation = 0.24
    private(set) var sampleCount = 0
    private(set) var lastTimestamp: MIDITimeStamp?
    private(set) var lastBeat: Double?

    mutating func reset(at timestamp: MIDITimeStamp?, beat: Double) {
        logTicksPerBeat = nil
        logDeviation = 0.24
        sampleCount = 0
        lastTimestamp = Self.valid(timestamp)
        lastBeat = beat
    }

    mutating func anchor(at timestamp: MIDITimeStamp?, beat: Double) {
        guard let timestamp = Self.valid(timestamp) else { return }
        if let lastTimestamp, timestamp <= lastTimestamp { return }
        if let lastBeat, beat <= lastBeat { return }
        lastTimestamp = timestamp
        lastBeat = beat
    }

    /// Returns broad corroborating evidence. Timing can add or remove less than one point and
    /// therefore cannot override a strong pitch disagreement.
    func compatibility(at timestamp: MIDITimeStamp?, beat: Double) -> Double {
        guard let sample = sample(at: timestamp, beat: beat),
              let center = logTicksPerBeat else { return 0 }
        let residual = abs(sample - center)
        let scale = max(0.20, logDeviation * 2.8)
        return max(-0.55, 0.32 - residual / scale * 0.32)
    }

    mutating func observe(at timestamp: MIDITimeStamp?, beat: Double) {
        defer { anchor(at: timestamp, beat: beat) }
        guard let sample = sample(at: timestamp, beat: beat) else { return }
        guard let center = logTicksPerBeat else {
            logTicksPerBeat = sample
            sampleCount = 1
            return
        }

        let residual = sample - center
        // Extreme pauses and transport discontinuities reduce timing usefulness but do not drag
        // the tempo estimate away from the performer's established pulse.
        guard abs(residual) <= Foundation.log(5.0) else {
            logDeviation = min(1.2, logDeviation * 1.2)
            return
        }
        let clipped = min(max(residual, -0.55), 0.55)
        let rate = sampleCount < 4 ? 0.28 : 0.16
        logTicksPerBeat = center + clipped * rate
        logDeviation = max(0.08, logDeviation * 0.82 + abs(residual) * 0.18)
        sampleCount += 1
    }

    var estimatedTicksPerBeat: Double? {
        logTicksPerBeat.map(Foundation.exp)
    }

    private func sample(at timestamp: MIDITimeStamp?, beat: Double) -> Double? {
        guard let previousTimestamp = lastTimestamp,
              let timestamp = Self.valid(timestamp), timestamp > previousTimestamp,
              let previousBeat = lastBeat, beat > previousBeat else { return nil }
        let beatDistance = beat - previousBeat
        let ticks = Double(timestamp - previousTimestamp) / beatDistance
        guard ticks.isFinite, ticks > 0 else { return nil }
        return Foundation.log(ticks)
    }

    private static func valid(_ timestamp: MIDITimeStamp?) -> MIDITimeStamp? {
        guard let timestamp, timestamp != 0 else { return nil }
        return timestamp
    }
}

private struct RobustTimingScale {
    private(set) var logCenter: Double?
    private(set) var logDeviation = 0.35
    private(set) var sampleCount = 0

    mutating func reset() {
        logCenter = nil
        logDeviation = 0.35
        sampleCount = 0
    }

    mutating func observe(_ ticks: Double) {
        guard ticks.isFinite, ticks > 0 else { return }
        let sample = Foundation.log(ticks)
        guard let center = logCenter else {
            logCenter = sample
            sampleCount = 1
            return
        }
        let residual = sample - center
        let clipped = min(max(residual, -0.7), 0.7)
        let rate = sampleCount < 5 ? 0.24 : 0.12
        logCenter = center + clipped * rate
        logDeviation = max(0.10, logDeviation * 0.84 + abs(residual) * 0.16)
        sampleCount += 1
    }

    func support(for ticks: Double) -> Double {
        guard ticks > 0, let center = logCenter, sampleCount >= 2 else { return 0 }
        let residual = abs(Foundation.log(ticks) - center)
        let scale = max(0.22, logDeviation * 3)
        return max(-1, min(1, 0.6 - residual / scale))
    }

    var estimate: Double? { logCenter.map(Foundation.exp) }
}

/// Timing evidence shared by gesture assembly and the committed local alignment path.
///
/// No method returns a Boolean boundary decision. The caller must combine these bounded values
/// with pitch membership, release state, score structure, and sequential evidence.
struct PerformanceTimingModel {
    struct GestureHint {
        let estimatedInterOnsetTicks: Double?
        let estimatedChordSpanTicks: Double?
        let reliability: Double

        /// Positive values favor a new gesture; negative values favor another chord member.
        func boundaryEvidence(
            gestureStartedAt: MIDITimeStamp?,
            lastAttackAt: MIDITimeStamp?,
            newAttackAt: MIDITimeStamp
        ) -> Double {
            guard newAttackAt != 0 else { return 0 }
            var evidence = 0.0
            var count = 0
            if let lastAttackAt, lastAttackAt != 0, newAttackAt > lastAttackAt,
               let interOnset = estimatedInterOnsetTicks, interOnset > 0 {
                let ratio = Double(newAttackAt - lastAttackAt) / interOnset
                evidence += min(1, max(-1, Foundation.log(max(ratio, 0.001)) / 1.5))
                count += 1
            }
            if let gestureStartedAt, gestureStartedAt != 0, newAttackAt > gestureStartedAt,
               let chordSpan = estimatedChordSpanTicks, chordSpan > 0 {
                let ratio = Double(newAttackAt - gestureStartedAt) / chordSpan
                evidence += min(1, max(-1, Foundation.log(max(ratio, 0.001)) / 1.8))
                count += 1
            }
            guard count > 0 else { return 0 }
            return evidence / Double(count) * reliability
        }
    }

    private(set) var localClock = PerformanceTempoTracker()
    private var blockChordSpan = RobustTimingScale()
    private var rolledChordSpan = RobustTimingScale()
    private var shortNoteDwell = RobustTimingScale()
    private var articulationRatio = RobustTimingScale()

    mutating func reset() {
        localClock = PerformanceTempoTracker()
        blockChordSpan.reset()
        rolledChordSpan.reset()
        shortNoteDwell.reset()
        articulationRatio.reset()
    }

    mutating func anchorLocal(at timestamp: MIDITimeStamp?, beat: Double) {
        localClock.anchor(at: timestamp, beat: beat)
    }

    func localTransitionScore(at timestamp: MIDITimeStamp?, beat: Double) -> Double {
        localClock.compatibility(at: timestamp, beat: beat)
    }

    mutating func observeLocalTransition(at timestamp: MIDITimeStamp?, beat: Double) {
        localClock.observe(at: timestamp, beat: beat)
    }

    mutating func adopt(_ tracker: PerformanceTempoTracker) {
        localClock = tracker
    }

    mutating func observeCompletedGesture(
        _ gesture: PerformanceGesture,
        attack: EngravingReference.Attack,
        expectedDurationBeats: Double,
        matchQuality: Double
    ) {
        guard matchQuality >= 0.72,
              let start = gesture.startedAt,
              start != 0 else { return }
        if let end = gesture.lastAttackAt, end > start {
            let span = Double(end - start)
            switch attack {
            case .block: blockChordSpan.observe(span)
            case .rolled: rolledChordSpan.observe(span)
            }
        }

        if gesture.pitchMask.nonzeroBitCount == 1,
           let release = gesture.lastReleaseAt, release > start {
            let dwell = Double(release - start)
            shortNoteDwell.observe(dwell)
            if let beatTicks = localClock.estimatedTicksPerBeat,
               expectedDurationBeats > 0 {
                articulationRatio.observe(dwell / (beatTicks * expectedDurationBeats))
            }
        }
    }

    func gestureHint(for attack: EngravingReference.Attack) -> GestureHint {
        let span = attack == .rolled ? rolledChordSpan.estimate : blockChordSpan.estimate
        let samples = max(
            localClock.sampleCount,
            attack == .rolled ? rolledChordSpan.sampleCount : blockChordSpan.sampleCount
        )
        return GestureHint(
            estimatedInterOnsetTicks: localClock.estimatedTicksPerBeat,
            estimatedChordSpanTicks: span,
            reliability: min(1, Double(samples) / 5)
        )
    }

    /// Weak evidence that a completed single-note gesture was an accidental insertion.
    func mistakeEvidence(
        for gesture: PerformanceGesture,
        expectedDurationBeats: Double
    ) -> Double {
        guard gesture.pitchMask.nonzeroBitCount == 1,
              let start = gesture.startedAt,
              let release = gesture.lastReleaseAt,
              release > start else { return 0 }
        let dwell = Double(release - start)
        let learned = shortNoteDwell.support(for: dwell)
        guard let beatTicks = localClock.estimatedTicksPerBeat else { return learned * -0.1 }
        let relative = dwell / beatTicks
        let shortSupport = max(0, min(1, (0.22 - relative) / 0.18))
        let durationRatio = expectedDurationBeats > 0
            ? dwell / (beatTicks * expectedDurationBeats)
            : relative
        let articulationSupport = max(0, -articulationRatio.support(for: durationRatio))
        return shortSupport * 0.35 + articulationSupport * 0.15 - learned * 0.06
    }
}
