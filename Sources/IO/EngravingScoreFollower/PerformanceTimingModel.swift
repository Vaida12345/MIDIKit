//
//  PerformanceTimingModel.swift
//  MIDIKit
//

import CoreMIDI
import Darwin
import Foundation


/// A robust latent tempo clock copied with each alignment hypothesis.
///
/// Tempo is represented in log host-time ticks per score beat. The heavy-tailed likelihood gives
/// timing substantial influence when it is consistent, while pauses, rubato, bad clocks, and
/// transport discontinuities remain survivable.
struct PerformanceTempoTracker {
    private(set) var logTicksPerBeat: Double?
    private(set) var logDeviation: Double = 0.30
    private(set) var sampleCount: Int = 0
    private(set) var lastTimestamp: MIDITimeStamp?
    private(set) var lastBeat: Double?

    init(calibration: PerformanceTempoCalibration? = nil) {
        if let calibration {
            logTicksPerBeat = calibration.logTicksPerBeat
            logDeviation = calibration.logDeviation
            sampleCount = calibration.sampleCount
        }
    }

    mutating func beginEpisode(at timestamp: MIDITimeStamp?, beat: Double) {
        lastTimestamp = timestamp
        lastBeat = beat
    }

    /// Student-t-like log likelihood, normalized so a well-timed transition contributes zero.
    /// Invalid timestamp pairs are neutral rather than contradictory.
    func transitionLogLikelihood(at timestamp: MIDITimeStamp?, beat: Double) -> Double {
        guard let sample = tempoSample(at: timestamp, beat: beat),
              let center = logTicksPerBeat else { return 0 }
        let scale = max(0.18, logDeviation)
        let standardized = (sample - center) / scale
        return max(-2.4, -1.5 * Foundation.log1p(standardized * standardized / 3))
    }

    /// Weak change-point evidence from a gap. It changes the prior odds of a restart but never
    /// selects a destination and is unavailable until a tempo has actually been learned.
    func pauseEvidence(at timestamp: MIDITimeStamp?) -> Double {
        guard let timestamp, let previous = lastTimestamp, timestamp > previous,
              let ticksPerBeat = estimatedTicksPerBeat else { return 0 }
        let beats = Double(timestamp - previous) / ticksPerBeat
        guard beats > 1.75 else { return 0 }
        return min(1.6, (beats - 1.75) * 0.42)
    }

    mutating func observeTransition(at timestamp: MIDITimeStamp?, beat: Double) {
        defer {
            if let timestamp { lastTimestamp = timestamp }
            lastBeat = beat
        }
        guard let sample = tempoSample(at: timestamp, beat: beat) else { return }
        guard let center = logTicksPerBeat else {
            logTicksPerBeat = sample
            sampleCount = 1
            return
        }

        let residual = sample - center
        // A long hesitation is a change-point cue, not a tempo measurement.
        guard abs(residual) <= Foundation.log(4.0) else {
            logDeviation = min(0.9, logDeviation * 1.08)
            return
        }
        let clipped = min(0.50, max(-0.50, residual))
        let learningRate = sampleCount < 5 ? 0.24 : 0.10
        logTicksPerBeat = center + clipped * learningRate
        logDeviation = max(0.10, logDeviation * 0.88 + abs(residual) * 0.12)
        sampleCount += 1
    }

    /// Starts a new timing episode while retaining the performer's learned scale.
    func detached(at timestamp: MIDITimeStamp?, beat: Double) -> Self {
        var copy = self
        copy.lastTimestamp = timestamp
        copy.lastBeat = beat
        return copy
    }

    var estimatedTicksPerBeat: Double? { logTicksPerBeat.map(Foundation.exp) }

    var calibration: PerformanceTempoCalibration? {
        guard let logTicksPerBeat else { return nil }
        return PerformanceTempoCalibration(
            logTicksPerBeat: logTicksPerBeat,
            logDeviation: logDeviation,
            sampleCount: sampleCount
        )
    }

    private func tempoSample(at timestamp: MIDITimeStamp?, beat: Double) -> Double? {
        guard let timestamp, let previousTimestamp = lastTimestamp,
              timestamp > previousTimestamp,
              let previousBeat = lastBeat, beat > previousBeat else { return nil }
        let ticksPerBeat = Double(timestamp - previousTimestamp) / (beat - previousBeat)
        guard ticksPerBeat.isFinite, ticksPerBeat > 0 else { return nil }
        return Foundation.log(ticksPerBeat)
    }
}

struct PerformanceTempoCalibration {
    let logTicksPerBeat: Double
    let logDeviation: Double
    let sampleCount: Int
}

/// Shared performer calibration that survives `userReset()` but not reference replacement.
struct PerformanceTimingModel {
    private(set) var calibration: PerformanceTempoCalibration?
    private var blockSpan: RobustPositiveEstimate
    private var rolledSpan: RobustPositiveEstimate
    private var dwellRatio = RobustPositiveEstimate(initial: 0.65)

    init() {
        blockSpan = RobustPositiveEstimate(initial: Self.hostTicks(seconds: 0.045))
        rolledSpan = RobustPositiveEstimate(initial: Self.hostTicks(seconds: 0.22))
    }

    mutating func hardReset() {
        calibration = nil
        blockSpan = RobustPositiveEstimate(initial: Self.hostTicks(seconds: 0.045))
        rolledSpan = RobustPositiveEstimate(initial: Self.hostTicks(seconds: 0.22))
        dwellRatio = RobustPositiveEstimate(initial: 0.65)
    }

    func newClock() -> PerformanceTempoTracker {
        PerformanceTempoTracker(calibration: calibration)
    }

    mutating func adopt(_ clock: PerformanceTempoTracker) {
        if let candidate = clock.calibration,
           calibration == nil || candidate.sampleCount >= (calibration?.sampleCount ?? 0) {
            calibration = candidate
        }
    }

    mutating func observeOnsetSpan(
        ticks: Double,
        attack: EngravingReference.Attack
    ) {
        guard ticks.isFinite, ticks > 0 else { return }
        if attack == .rolled { rolledSpan.observe(ticks) }
        else { blockSpan.observe(ticks) }
    }

    mutating func observeDwell(ticks: Double, writtenBeats: Double) {
        guard ticks.isFinite, ticks > 0, writtenBeats > 0,
              let tempo = calibration.map({ Foundation.exp($0.logTicksPerBeat) }) else { return }
        dwellRatio.observe(ticks / (tempo * writtenBeats))
    }

    func dwellLogLikelihood(ticks: Double, writtenBeats: Double) -> Double {
        guard ticks.isFinite, ticks > 0, writtenBeats > 0,
              let tempo = calibration.map({ Foundation.exp($0.logTicksPerBeat) }) else { return 0 }
        let ratio = ticks / (tempo * writtenBeats)
        guard ratio.isFinite, ratio > 0 else { return 0 }
        let residual = Foundation.log(ratio / dwellRatio.value)
        return max(-0.55, -0.5 * Foundation.log1p(residual * residual / 0.36))
    }

    /// Likelihood that another serialized attack belongs to the same performed onset. This is
    /// deliberately soft and broad; pitch evidence remains free to override it for slow rolls.
    func sameOnsetLogLikelihood(
        elapsedTicks: Double?,
        attack: EngravingReference.Attack
    ) -> Double {
        guard let elapsedTicks, elapsedTicks > 0 else { return 0 }
        let center = attack == .rolled ? rolledSpan.value : blockSpan.value
        let ratio = elapsedTicks / max(1, center)
        return ratio <= 1 ? 0 : max(-0.85, -Foundation.log1p(ratio - 1) * 0.42)
    }

    /// Prior evidence for opening a new performed onset before tempo has been learned. Core MIDI
    /// timestamps use host-clock ticks, so the scale is derived from the host clock rather than a
    /// machine-specific integer constant. The result is deliberately bounded: a very small gap is
    /// strong evidence for a serialized chord, never a hard transition veto.
    func newOnsetLogLikelihood(
        elapsedTicks: Double?,
        precedingAttack: EngravingReference.Attack
    ) -> Double {
        guard let elapsedTicks, elapsedTicks > 0 else { return 0 }
        let center = precedingAttack == .rolled ? rolledSpan.value : blockSpan.value
        let ratio = elapsedTicks / max(1, center)
        guard ratio < 0.75 else { return 0 }
        return max(-1.55, Foundation.log(max(0.08, ratio / 0.75)) * 0.58)
    }

    /// Zero means the timing clearly permits a boundary; one means it strongly resembles another
    /// serialized attack in the same onset. Pitch and release evidence remain free to override it.
    func sameOnsetSupport(
        elapsedTicks: Double?,
        attack: EngravingReference.Attack
    ) -> Double {
        // Missing, equal, and nonmonotonic timestamp relationships are unavailable evidence.
        // Physical key overlap is handled by the caller and must not cause us to invent a
        // midpoint timing observation when the host clock cannot describe this relationship.
        guard let elapsedTicks, elapsedTicks > 0 else { return 0 }
        let center = attack == .rolled ? rolledSpan.value : blockSpan.value
        let ratio = elapsedTicks / max(1, center)
        if ratio <= 0.45 { return 1 }
        if ratio >= 1.5 { return 0 }
        return (1.5 - ratio) / 1.05
    }

    private static func hostTicks(seconds: Double) -> Double {
        max(1, seconds * hostTicksPerSecond)
    }

    /// Core MIDI timestamps use the Mach absolute-time clock on every supported Apple platform.
    /// Its timebase expresses nanoseconds per host tick as `numer / denom`.
    private static let hostTicksPerSecond: Double = {
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS,
              timebase.numer > 0,
              timebase.denom > 0 else {
            // All currently supported Apple platforms provide a valid Mach timebase. Keeping a
            // nanosecond fallback makes initialization total if the kernel call ever fails.
            return 1_000_000_000
        }
        return 1_000_000_000 * Double(timebase.denom) / Double(timebase.numer)
    }()
}

private struct RobustPositiveEstimate {
    private(set) var value: Double
    private var sampleCount = 0

    init(initial: Double) { value = initial }

    mutating func observe(_ sample: Double) {
        guard sample.isFinite, sample > 0 else { return }
        let center = Foundation.log(value)
        let residual = Foundation.log(sample) - center
        let clipped = min(1.1, max(-1.1, residual))
        let rate = sampleCount < 6 ? 0.20 : 0.08
        value = Foundation.exp(center + clipped * rate)
        sampleCount += 1
    }
}
