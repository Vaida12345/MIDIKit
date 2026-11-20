//
//  TimeWarpTests.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import Testing
import Foundation
import MIDIKit
@testable
import IndexedTrack


// MARK: - Synthetic pieces

extension IndexedTrackRNG {
    
    /// A uniform value in `0..<1`.
    fileprivate mutating func uniform() -> Double {
        Double(self.next() >> 11) / Double(1 << 53)
    }
    
    /// A standard normal value, by the Box-Muller transform.
    fileprivate mutating func gaussian() -> Double {
        let first = Swift.max(self.uniform(), 1e-12)
        let second = self.uniform()
        return (-2 * log(first)).squareRoot() * cos(2 * .pi * second)
    }
}


/// A performance that is made from a sheet by a known warp and known corruptions, so the right answer is exact everywhere. All times are in beats.
private struct Scenario: Sendable, CustomTestStringConvertible {
    
    var name: String
    
    /// The share of the performance's tempo to the sheet's: performance beats per sheet beat.
    var ratio = 1.0
    
    /// Where sheet time 0 is in the performance.
    var offset = 2.0
    
    /// The total change of the logarithm of the tempo over the piece: the tempo drifts smoothly by a factor of `exp(drift)`.
    var drift = 0.0
    
    /// The standard deviation of a smooth random logarithm of the tempo, made of low frequencies with a decaying spectrum.
    var randomWarp = 0.0
    
    /// Where a pause starts, as a share of the piece, and how long it is and how much it stretches the sheet time, in sheet beats.
    var pauseAt: Double?
    var pauseLength = 2.0
    var pauseStretch = 1.0
    
    /// The standard deviation of the timing noise of each chord, and the widest roll of a chord, in beats.
    var jitter = 0.0
    var roll = 0.0
    
    /// The share of the notes that are missing in the performance, and the share of notes that are added to it.
    var missing = 0.0
    var extra = 0.0
    
    /// The number of chords of other music before and after the piece in the performance.
    var junkChords = 0
    
    var seed: UInt64 = 1
    
    /// The tolerance on the 95th percentile of the error, in beats.
    var tolerance = 0.03
    
    var testDescription: String { self.name }
}


/// A strictly increasing function of time that is given by its values at a regular step.
private struct Curve: Sendable {
    
    var step: Double
    
    var values: [Double]
    
    func callAsFunction(_ time: Double) -> Double {
        let position = time / self.step
        let index = Swift.min(Swift.max(Int(position.rounded(.down)), 0), self.values.count - 2)
        let fraction = position - Double(index)
        return self.values[index] + (self.values[index + 1] - self.values[index]) * fraction
    }
    
    /// The warp through the curve at the given step.
    func warp(until end: Double, every step: Double) -> TimeWarp {
        var knots: [TimeWarp.Knot] = []
        var time = 0.0
        while time <= end {
            knots.append(TimeWarp.Knot(source: time, target: self(time)))
            time += step
        }
        return TimeWarp(knots: knots)!
    }
}


/// A sheet to test with: a line that wanders, with a chord now and then. Chords are notes that share an onset.
private func toySheet(chords: Int, seed: UInt64) -> [MIDINote] {
    var rng = IndexedTrackRNG(seed: seed)
    var notes: [MIDINote] = []
    var time = 1.0
    var pitch = 60
    let steps = [0.5, 0.5, 1, 0.25, 1.5, 0.5]
    for _ in 0..<chords {
        let size = rng.uniform() < 0.25 ? 2 + rng.int(0...2) : 1
        for index in 0..<size {
            notes.append(note(time, time + 0.1, UInt8(Swift.min(108, Swift.max(21, pitch + index * 4)))))
        }
        pitch = Swift.min(84, Swift.max(40, pitch + rng.int(0...8) - 4))
        time += steps[rng.int(0...steps.count - 1)]
    }
    return notes
}


/// Plays the sheet as the scenario says, and returns the truth: where each sheet time is in the performance.
private func realize(_ scenario: Scenario, sheet: [MIDINote]) -> (performance: [MIDINote], truth: Curve) {
    var rng = IndexedTrackRNG(seed: scenario.seed)
    let length = (sheet.map(\.onset).max() ?? 1) + 1
    
    let waves: [(amplitude: Double, phase: Double)] = (1...8).map { index in
        (scenario.randomWarp * rng.gaussian() / pow(Double(index), 1.2), rng.uniform() * 2 * .pi)
    }
    func logTempo(_ time: Double) -> Double {
        var value = scenario.drift * (time / length - 0.5)
        for (index, wave) in waves.enumerated() {
            value += wave.amplitude * sin(2 * .pi * Double(index + 1) * time / length + wave.phase)
        }
        return value
    }
    func stretch(_ time: Double) -> Double {
        guard let at = scenario.pauseAt else { return 1 }
        let start = at * length
        return time >= start && time < start + scenario.pauseLength ? scenario.pauseStretch : 1
    }
    
    let step = 0.02
    var values: [Double] = []
    var performanceTime = scenario.offset
    var time = 0.0
    while time <= length + step {
        values.append(performanceTime)
        performanceTime += scenario.ratio * exp(logTempo(time)) * stretch(time) * step
        time += step
    }
    let truth = Curve(step: step, values: values)
    
    // The chords of the sheet are the notes that share an onset.
    let sorted = sheet.sorted(by: isOrdered)
    var performance: [MIDINote] = []
    var start = 0
    while start < sorted.count {
        var end = start + 1
        while end < sorted.count, sorted[end].onset == sorted[start].onset {
            end += 1
        }
        let base = truth(sorted[start].onset) + rng.gaussian() * scenario.jitter
        let spread = rng.uniform() * scenario.roll
        let order = (start..<end).shuffled(using: &rng)
        for index in start..<end {
            if rng.uniform() < scenario.missing { continue }
            let rank = Double(order.firstIndex(of: index)!) / Double(Swift.max(1, end - start - 1))
            let onset = Swift.max(0, base + rank * spread + rng.gaussian() * scenario.jitter * 0.3)
            performance.append(note(onset, onset + 0.1, sorted[index].pitch, velocity: sorted[index].velocity))
        }
        start = end
    }
    
    // Notes added near existing ones.
    let added = Int(scenario.extra * Double(performance.count))
    let existing = performance
    for _ in 0..<added where !existing.isEmpty {
        let host = existing[rng.int(0...existing.count - 1)]
        var delta = rng.int(-7...6)
        if delta >= 0 { delta += 1 }
        let onset = Swift.max(0, host.onset + (rng.uniform() - 0.5) * 0.8)
        performance.append(note(onset, onset + 0.1, UInt8(Swift.min(108, Swift.max(21, Int(host.pitch) + delta))), velocity: 60))
    }
    
    // Other music before and after the piece.
    if scenario.junkChords > 0, let first = performance.map(\.onset).min(), let last = performance.map(\.onset).max() {
        for index in 0..<scenario.junkChords {
            let before = first - 1 - 0.5 * Double(scenario.junkChords - index)
            let after = last + 1 + 0.5 * Double(index + 1)
            for onset in [before, after] {
                performance.append(note(onset, onset + 0.1, UInt8(rng.int(40...90))))
            }
        }
    }
    return (performance, truth)
}


/// The scenarios of the recovery tests, with the tolerance on the 95th percentile of the error that each is held to.
///
/// The tolerances are those the scratch lab measured on real sheets with margin: 5-9 ms for a clean warp, 31-35 ms for 8% missing or extra notes and 51-60 ms for everything at once, in beats at 120 BPM twice that.
private let recoveryScenarios: [Scenario] = [
    Scenario(name: "constant ratio", ratio: 1.37, offset: 2.4),
    Scenario(name: "gradual drift", ratio: 1.0, drift: log(1.4 / 0.8)),
    Scenario(name: "random rubato", randomWarp: 0.35),
    Scenario(name: "a pause", ratio: 1.1, pauseAt: 0.5, pauseLength: 2, pauseStretch: 12),
    Scenario(name: "8% missing notes", ratio: 1.2, jitter: 0.03, missing: 0.08, tolerance: 0.09),
    Scenario(name: "8% extra notes", ratio: 1.2, jitter: 0.03, extra: 0.08, tolerance: 0.09),
    Scenario(name: "everything at once", ratio: 1.15, randomWarp: 0.3, pauseAt: 0.4, pauseLength: 1.6, pauseStretch: 8, jitter: 0.04, roll: 0.12, missing: 0.05, extra: 0.05, tolerance: 0.16)
]


/// The value at the share `fraction` of the sorted values, by nearest rank.
private func percentile(_ values: [Double], _ fraction: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    return sorted[Swift.min(sorted.count - 1, Swift.max(0, Int((fraction * Double(sorted.count)).rounded(.up)) - 1))]
}

/// Prints the figures of a recovery test, for the report.
private func report(_ name: String, errors: [Double], tolerance: Double) {
    func format(_ value: Double) -> String { String(format: "%.4f", value) }
    print("[TimeWarp] \(name): \(errors.count) sheet chords, error median \(format(percentile(errors, 0.5))), p95 \(format(percentile(errors, 0.95))), p99 \(format(percentile(errors, 0.99))), max \(format(errors.max() ?? 0)) beats; p95 tolerance \(tolerance)")
}


// MARK: - Random events, for the unit tests of the search

/// The events of chords that hold the given keys at the given times.
private func events(times: [Double], keys: [[Int]]) -> TimeWarp.Events {
    var low: [UInt64] = []
    var high: [UInt64] = []
    var sizes: [Float] = []
    for chord in keys {
        var lowKeys: UInt64 = 0
        var highKeys: UInt64 = 0
        for key in chord {
            let bit = key - 21
            if bit < 64 {
                lowKeys |= 1 << UInt64(bit)
            } else {
                highKeys |= 1 << UInt64(bit - 64)
            }
        }
        low.append(lowKeys)
        high.append(highKeys)
        sizes.append(Float(chord.count))
    }
    return TimeWarp.Events(times: times, low: low, high: high, sizes: sizes)
}

/// A random sheet and a performance of it, as events: a slower tempo with timing noise, missing and extra chords, chords with a changed key, and unrelated chords around. The keys straddle the boundary between the two words of a chord's keys.
private func randomPiece(seed: UInt64, chords: Int, junk: Int = 0, keys range: ClosedRange<Int> = 78...92) -> (sheet: TimeWarp.Events, performance: TimeWarp.Events) {
    var rng = IndexedTrackRNG(seed: seed)
    var sheetTimes: [Double] = []
    var sheetKeys: [[Int]] = []
    var time = 0.0
    for _ in 0..<chords {
        time += [0.25, 0.5, 0.5, 1, 1.5][rng.int(0...4)]
        var chord = Set<Int>()
        let size = 1 + rng.int(0...2)
        while chord.count < size {
            chord.insert(rng.int(range))
        }
        sheetTimes.append(time)
        sheetKeys.append(chord.sorted())
    }
    
    var performanceTimes: [Double] = []
    var performanceKeys: [[Int]] = []
    func randomChord() -> [Int] {
        var chord = Set<Int>()
        for _ in 0..<(1 + rng.int(0...2)) {
            chord.insert(rng.int(range))
        }
        return chord.sorted()
    }
    for index in 0..<junk {
        performanceTimes.append(-0.5 * Double(junk - index))
        performanceKeys.append(randomChord())
    }
    for index in 0..<chords {
        if rng.uniform() < 0.08 { continue } // missing
        var chord = sheetKeys[index]
        if rng.uniform() < 0.1 {
            if chord.count > 1 {
                chord.remove(at: rng.int(0...chord.count - 1))
            } else {
                chord = Array(Set(chord + [rng.int(range)])).sorted()
            }
        }
        let played = 3 + 1.2 * sheetTimes[index] + rng.gaussian() * 0.02
        performanceTimes.append(played)
        performanceKeys.append(chord)
        if rng.uniform() < 0.06 { // extra
            performanceTimes.append(played + 0.1)
            performanceKeys.append(randomChord())
        }
    }
    let last = performanceTimes.last ?? 0
    for index in 0..<junk {
        performanceTimes.append(last + 1 + 0.5 * Double(index))
        performanceKeys.append(randomChord())
    }
    return (events(times: sheetTimes, keys: sheetKeys), events(times: performanceTimes, keys: performanceKeys))
}


// MARK: - Plain references of the searches

/// The score of the best pilot alignment by a plain O(*n* *m*) dynamic program with no band and no tricks, to check the banded one against.
private func referencePilotScore(sheet: TimeWarp.Events, performance: TimeWarp.Events, scoring: TimeWarp.Scoring) -> Double {
    let n = sheet.count
    let m = performance.count
    let negInf = -1e30
    let gapOpen = Double(scoring.gapOpen)
    let gapExtend = Double(scoring.gapExtend)
    let mismatch = Double(scoring.mismatch)
    
    var paired = [[Double]](repeating: [Double](repeating: negInf, count: m + 1), count: n + 1)
    var sheetGap = paired
    var performanceGap = paired
    paired[0][0] = 0
    for column in 1...m {
        performanceGap[0][column] = 0
    }
    for row in 1...n {
        sheetGap[row][0] = 0
    }
    
    var best = negInf
    for row in 1...n {
        for column in 0...m {
            if column > 0 {
                let shared = sheet.sharedCount(row - 1, with: performance, column - 1)
                if shared >= 1 {
                    let score = 2 * Double(shared) - mismatch * ((Double(sheet.sizes[row - 1]) - Double(shared)) + (Double(performance.sizes[column - 1]) - Double(shared)))
                    let from = Swift.max(paired[row - 1][column - 1], sheetGap[row - 1][column - 1], performanceGap[row - 1][column - 1])
                    if from > negInf / 2 { paired[row][column] = from + score }
                }
                let above = Swift.max(paired[row - 1][column] - gapOpen, sheetGap[row - 1][column] - gapExtend, performanceGap[row - 1][column] - gapOpen)
                if above > negInf / 2 { sheetGap[row][column] = above }
                let side = Swift.max(paired[row][column - 1] - gapOpen, sheetGap[row][column - 1] - gapOpen, performanceGap[row][column - 1] - gapExtend)
                if side > negInf / 2 { performanceGap[row][column] = side }
            }
            if row == n || column == m {
                best = Swift.max(best, paired[row][column], sheetGap[row][column], performanceGap[row][column])
            }
        }
    }
    return best
}

/// The score of a sequence of pairs as the pilot alignment counts it: what the pairs earn, less the cost of the chords that lie between them, and of the chords before the first and after the last pair, of which one of the two sides is free.
private func pilotPathScore(_ pairs: [TimeWarp.Pair], sheet: TimeWarp.Events, performance: TimeWarp.Events, scoring: TimeWarp.Scoring) -> Double {
    let gapOpen = Double(scoring.gapOpen)
    let gapExtend = Double(scoring.gapExtend)
    let mismatch = Double(scoring.mismatch)
    func gap(_ count: Int) -> Double { count == 0 ? 0 : gapOpen + gapExtend * Double(count - 1) }
    
    guard let first = pairs.first, let last = pairs.last else { return 0 }
    var score = 0.0
    for pair in pairs {
        let i = Int(pair.sheet)
        let j = Int(pair.performance)
        let shared = Double(sheet.sharedCount(i, with: performance, j))
        score += 2 * shared - mismatch * ((Double(sheet.sizes[i]) - shared) + (Double(performance.sizes[j]) - shared))
    }
    for (previous, next) in zip(pairs, pairs.dropFirst()) {
        score -= gap(Int(next.sheet) - Int(previous.sheet) - 1) + gap(Int(next.performance) - Int(previous.performance) - 1)
    }
    // Before the first pair and after the last, a side that is used up is free, and of two sides that are not, the cheaper is paid.
    let leadingSheet = Int(first.sheet)
    let leadingPerformance = Int(first.performance)
    if leadingSheet > 0 && leadingPerformance > 0 { score -= Swift.min(gap(leadingSheet), gap(leadingPerformance)) }
    let trailingSheet = sheet.count - 1 - Int(last.sheet)
    let trailingPerformance = performance.count - 1 - Int(last.performance)
    if trailingSheet > 0 && trailingPerformance > 0 { score -= Swift.min(gap(trailingSheet), gap(trailingPerformance)) }
    return score
}

/// The score of the best path of the tempo search by a plain dynamic program over every state, in double precision with no band and no vectors.
private func referenceTempoScore(sheet: TimeWarp.Events, performance: TimeWarp.Events, rate: Double, parameters: TimeWarp.Parameters) -> Double {
    let n = sheet.count
    let m = performance.count
    let bins = parameters.tempoBinCount
    let middle = bins / 2
    let negInf = -1e30
    let step = log(parameters.tempoBinRatio)
    let gapOpen = parameters.gapOpen
    let gapExtend = parameters.gapExtend
    func prior(_ bin: Int) -> Double {
        let z = Double(bin - middle) * step / parameters.tempoPriorSigma
        return -0.5 * z * z
    }
    func extraCost(_ extra: Int) -> Double { extra == 0 ? 0 : gapOpen + gapExtend * Double(extra - 1) }
    func skipCost(_ skip: Int) -> Double { skip <= 1 ? 0 : gapOpen + gapExtend * Double(skip - 2) }
    
    var smooth = [[[Double]]](repeating: [[Double]](repeating: [Double](repeating: negInf, count: bins), count: n), count: m)
    var prefixValue = negInf
    var prefixJ = -1
    var prefixI = -1
    for j in 0..<m {
        var values = [[Double]](repeating: [Double](repeating: negInf, count: bins), count: n)
        var rowValue = negInf
        var rowI = -1
        for i in 0..<n {
            let shared = sheet.sharedCount(i, with: performance, j)
            guard shared >= 1 else { continue }
            let emission = 2 * Double(shared) - parameters.mismatchPenalty * ((Double(sheet.sizes[i]) - Double(shared)) + (Double(performance.sizes[j]) - Double(shared)))
            for k in 0..<bins {
                var best = prior(k)
                let tempo = rate * exp(Double(k - middle) * step)
                for extra in 0...parameters.maximumExtras {
                    let earlier = j - 1 - extra
                    guard earlier >= 0 else { break }
                    let gapB = performance.times[j] - performance.times[earlier]
                    for skip in 0...parameters.maximumSkip {
                        let earlierI = i - skip
                        guard earlierI >= 0 else { break }
                        let carried = smooth[earlier][earlierI][k]
                        guard carried > negInf / 2 else { continue }
                        var cost = extraCost(extra) + skipCost(skip)
                        if skip == 0 {
                            cost += parameters.splitCost + parameters.timingWeight * Swift.min(parameters.timingCap, gapB / parameters.rollScale)
                        } else {
                            let expected = tempo * (sheet.times[i] - sheet.times[earlierI])
                            let sigma = (parameters.timingNoise * parameters.timingNoise + parameters.relativeTimingNoise * expected * parameters.relativeTimingNoise * expected).squareRoot()
                            let z = (gapB - expected) / sigma
                            cost += parameters.timingWeight * Swift.min(parameters.timingCap, 0.5 * z * z)
                        }
                        best = Swift.max(best, carried - cost)
                    }
                }
                if prefixJ >= 0, i > prefixI {
                    let penalty = 2 * gapOpen + gapExtend * Double((j - prefixJ - 1) + (i - prefixI - 1))
                    best = Swift.max(best, prefixValue - penalty + prior(k))
                }
                values[i][k] = best + emission
                if values[i][k] > rowValue {
                    rowValue = values[i][k]
                    rowI = i
                }
            }
        }
        if rowValue > prefixValue {
            prefixValue = rowValue
            prefixJ = j
            prefixI = rowI
        }
        for i in 0..<n {
            for k in 0..<bins {
                var best = values[i][k]
                if k > 0 { best = Swift.max(best, values[i][k - 1] - parameters.tempoMoveCost) }
                if k + 1 < bins { best = Swift.max(best, values[i][k + 1] - parameters.tempoMoveCost) }
                smooth[j][i][k] = best
            }
        }
    }
    return prefixValue
}

/// The best score that a sequence of pairs can have in the tempo search: the best choice of tempo states along it. Each step from a pair to the next is an ordinary step if the pairs are close enough, or a restart.
private func tempoPathScore(_ pairs: [TimeWarp.Pair], sheet: TimeWarp.Events, performance: TimeWarp.Events, rate: Double, parameters: TimeWarp.Parameters) -> Double {
    let bins = parameters.tempoBinCount
    let middle = bins / 2
    let step = log(parameters.tempoBinRatio)
    let gapOpen = parameters.gapOpen
    let gapExtend = parameters.gapExtend
    func prior(_ bin: Int) -> Double {
        let z = Double(bin - middle) * step / parameters.tempoPriorSigma
        return -0.5 * z * z
    }
    func extraCost(_ extra: Int) -> Double { extra == 0 ? 0 : gapOpen + gapExtend * Double(extra - 1) }
    func skipCost(_ skip: Int) -> Double { skip <= 1 ? 0 : gapOpen + gapExtend * Double(skip - 2) }
    
    var previous: (pair: TimeWarp.Pair, values: [Double])?
    for pair in pairs {
        let i = Int(pair.sheet)
        let j = Int(pair.performance)
        let shared = sheet.sharedCount(i, with: performance, j)
        let emission = 2 * Double(shared) - parameters.mismatchPenalty * ((Double(sheet.sizes[i]) - Double(shared)) + (Double(performance.sizes[j]) - Double(shared)))
        var values = [Double](repeating: -.infinity, count: bins)
        for k in 0..<bins {
            guard let (before, carried) = previous else {
                values[k] = prior(k) + emission
                continue
            }
            let earlierI = Int(before.sheet)
            let earlierJ = Int(before.performance)
            let extra = j - earlierJ - 1
            let skip = i - earlierI
            var best = -Double.infinity
            if extra >= 0, extra <= parameters.maximumExtras, skip >= 0, skip <= parameters.maximumSkip {
                var cost = extraCost(extra) + skipCost(skip)
                let gapB = performance.times[j] - performance.times[earlierJ]
                if skip == 0 {
                    cost += parameters.splitCost + parameters.timingWeight * Swift.min(parameters.timingCap, gapB / parameters.rollScale)
                } else {
                    let expected = rate * exp(Double(k - middle) * step) * (sheet.times[i] - sheet.times[earlierI])
                    let sigma = (parameters.timingNoise * parameters.timingNoise + parameters.relativeTimingNoise * expected * parameters.relativeTimingNoise * expected).squareRoot()
                    let z = (gapB - expected) / sigma
                    cost += parameters.timingWeight * Swift.min(parameters.timingCap, 0.5 * z * z)
                }
                for source in Swift.max(0, k - 1)...Swift.min(bins - 1, k + 1) {
                    best = Swift.max(best, carried[source] - (source == k ? 0 : parameters.tempoMoveCost) - cost)
                }
            }
            if i > earlierI {
                let penalty = 2 * gapOpen + gapExtend * Double((j - earlierJ - 1) + (i - earlierI - 1))
                best = Swift.max(best, carried.max()! - penalty + prior(k))
            }
            values[k] = best + emission
        }
        previous = (pair, values)
    }
    return previous?.values.max() ?? 0
}


/// A random piece with the hard parts of a performance put in on purpose: a block of foreign chords in the middle, a section of the sheet that the performance leaves out, and chords that the performance plays as two.
private func directedPiece(seed: UInt64) -> (sheet: TimeWarp.Events, performance: TimeWarp.Events) {
    var rng = IndexedTrackRNG(seed: seed)
    let count = 64
    var sheetTimes: [Double] = []
    var sheetKeys: [[Int]] = []
    var time = 0.0
    for _ in 0..<count {
        time += [0.25, 0.5, 0.5, 1, 1.5][rng.int(0...4)]
        var chord = Set<Int>()
        let size = 2 + rng.int(0...1)
        while chord.count < size {
            chord.insert(rng.int(60...100))
        }
        sheetTimes.append(time)
        sheetKeys.append(chord.sorted())
    }
    
    var times: [Double] = []
    var keys: [[Int]] = []
    let foreignAfter = 20 + rng.int(0...5)
    let missingFrom = 38 + rng.int(0...4)
    var delay = 0.0
    for index in 0..<count {
        // The performance leaves out nine chords of the sheet in a row.
        if index >= missingFrom && index < missingFrom + 9 { continue }
        let played = 2 + 1.25 * sheetTimes[index] + delay + rng.gaussian() * 0.01
        if rng.uniform() < 0.15 {
            // Rolled so far apart that the performance has two chords for one.
            let chord = sheetKeys[index]
            times.append(played)
            keys.append(Array(chord[0..<1]))
            times.append(played + 0.06)
            keys.append(Array(chord[1...]))
        } else {
            times.append(played)
            keys.append(sheetKeys[index])
        }
        if index == foreignAfter {
            // Ten chords of another piece, more than the search steps over as extra chords, and the performance goes on after them.
            for step in 0..<10 {
                times.append(played + 0.3 * Double(step + 1))
                keys.append([rng.int(60...100)])
            }
            delay = 3.3
        }
    }
    return (events(times: sheetTimes, keys: sheetKeys), events(times: times, keys: keys))
}

/// How the steps of a path arrive, by the sizes of the steps: with the limits of the parameters, a step is plain, has extra chords of the performance, skips chords of the sheet, is a split of one chord of the sheet, or is a restart.
private struct WaysOfArriving {
    
    var plain = 0
    var extras = 0
    var skips = 0
    var splits = 0
    var restarts = 0
    
    init(_ pairs: [TimeWarp.Pair], parameters: TimeWarp.Parameters) {
        for (previous, next) in zip(pairs, pairs.dropFirst()) {
            let extra = Int(next.performance) - Int(previous.performance) - 1
            let skip = Int(next.sheet) - Int(previous.sheet)
            if extra > parameters.maximumExtras || skip > parameters.maximumSkip {
                self.restarts += 1
            } else if skip == 0 {
                self.splits += 1
            } else if extra > 0 {
                self.extras += 1
            } else if skip >= 2 {
                self.skips += 1
            } else {
                self.plain += 1
            }
        }
    }
    
    static func + (lhs: WaysOfArriving, rhs: WaysOfArriving) -> WaysOfArriving {
        var result = lhs
        result.plain += rhs.plain
        result.extras += rhs.extras
        result.skips += rhs.skips
        result.splits += rhs.splits
        result.restarts += rhs.restarts
        return result
    }
    
    init() { }
    
    var description: String {
        "\(self.plain) plain, \(self.extras) with extra chords, \(self.skips) with skipped chords, \(self.splits) splits, \(self.restarts) restarts"
    }
}


/// The inputs of a reference test of the tempo search.
private struct TempoCase {
    
    var sheet: TimeWarp.Events
    
    var performance: TimeWarp.Events
    
    var parameters: TimeWarp.Parameters
    
    /// The tempo of the middle tempo state, as ``IndexedTrack/timeWarp(to:parameters:)`` takes it.
    var rate: Double {
        (self.performance.times.last! - self.performance.times.first!) / (self.sheet.times.last! - self.sheet.times.first!)
    }
    
    /// A piece of 12 to 34 chords and the generic constants.
    static func generic(seed: Int) -> TempoCase {
        let (sheet, performance) = randomPiece(seed: UInt64(seed) &+ 500, chords: 12 + seed * 2, junk: seed % 3)
        return TempoCase(sheet: sheet, performance: performance, parameters: .generic)
    }
    
    /// A piece of 25 chords and constants that change the shapes of the loops: few or many tempo states, none to many extra chords, a step of one chord to a step of nine.
    static func otherConstants(seed: Int) -> TempoCase {
        var parameters = TimeWarp.Parameters.generic
        parameters.tempoBinCount = [3, 5, 9, 33][seed]
        parameters.maximumExtras = [0, 1, 2, 4][seed]
        parameters.maximumSkip = [1, 2, 4, 9][seed]
        let (sheet, performance) = randomPiece(seed: UInt64(seed) &+ 700, chords: 25, junk: 2, keys: 60...100)
        return TempoCase(sheet: sheet, performance: performance, parameters: parameters)
    }
}


/// A profile that is not the generic one, to see that it is kept.
private struct TaggedProfile: AnalysisProfile {
    
    func formChords(in track: IndexedTrack) -> IndexedTrack.Chords {
        GenericProfile().formChords(in: track)
    }
}


/// The tests of `IndexedTrack.timeWarp(to:parameters:)`, `IndexedTrack.warped(by:)` and `TimeWarp`.
///
/// The name `TimeWarpTests` is taken by the tests of the old implementation on `IndexedContainer`, which `swift test --filter TimeWarpTests` runs as well.
@Suite(.timeLimit(.minutes(1)))
struct IndexedTrackTimeWarpTests {
    
    // MARK: The value
    
    @Test
    func rejectsKnotsThatAreNotAMonotoneMapping() {
        typealias Knot = TimeWarp.Knot
        #expect(TimeWarp(knots: []) == nil)
        #expect(TimeWarp(knots: [Knot(source: .nan, target: 0)]) == nil)
        #expect(TimeWarp(knots: [Knot(source: 0, target: .infinity)]) == nil)
        #expect(TimeWarp(knots: [Knot(source: 0, target: 0), Knot(source: 0, target: 1)]) == nil)
        #expect(TimeWarp(knots: [Knot(source: 0, target: 0), Knot(source: 1, target: 0)]) == nil)
        #expect(TimeWarp(knots: [Knot(source: 0, target: 1), Knot(source: 1, target: 0)]) == nil)
        #expect(TimeWarp(knots: [Knot(source: 1, target: 0), Knot(source: 0, target: 1)]) == nil)
        #expect(TimeWarp(knots: [Knot(source: 0, target: 0)]) != nil)
        #expect(TimeWarp(knots: [Knot(source: -2, target: 5), Knot(source: 0, target: 6), Knot(source: 3, target: 100)]) != nil)
    }
    
    @Test
    func mapsKnotsExactlyAndInterpolatesBetweenThem() throws {
        let warp = try #require(TimeWarp(knots: [.init(source: 0, target: 10), .init(source: 4, target: 14), .init(source: 6, target: 30)]))
        for knot in warp.knots {
            #expect(warp.map(knot.source) == knot.target)
        }
        #expect(warp.map(2) == 12)
        #expect(warp.map(5) == 22)
        #expect(warp.map(6) == 30)
    }
    
    @Test
    func continuesWithTheClampedSlopeBeyondTheEnds() throws {
        // Slopes 10 and 0.1, which are clamped to 3 and 0.3.
        let steep = try #require(TimeWarp(knots: [.init(source: 0, target: 0), .init(source: 10, target: 100)]))
        #expect(steep.map(11) == 103)
        #expect(steep.map(-1) == -3)
        let shallow = try #require(TimeWarp(knots: [.init(source: 0, target: 0), .init(source: 10, target: 1)]))
        #expect(abs(shallow.map(11) - 1.3) < 1e-12)
        #expect(abs(shallow.map(-1) - -0.3) < 1e-12)
        // A slope in range is continued as it is, from the end knot, with the slopes of the nearest segment at each end.
        let bent = try #require(TimeWarp(knots: [.init(source: 0, target: 0), .init(source: 1, target: 2), .init(source: 3, target: 3)]))
        #expect(bent.map(-1) == -2)
        #expect(abs(bent.map(5) - 4) < 1e-12)
    }
    
    @Test
    func aSingleKnotShifts() throws {
        let warp = try #require(TimeWarp(knots: [.init(source: 3, target: 8)]))
        #expect(warp.map(3) == 8)
        #expect(warp.map(0) == 5)
        #expect(warp.map(10) == 15)
    }
    
    @Test
    func identityChangesNothing() {
        for time in [-1e6, -3.25, -0.0, 0, 1e-9, 0.1, 17.5, 1234.567, 1e7] {
            #expect(TimeWarp.identity.map(time) == time)
        }
    }
    
    @Test(arguments: 0..<10)
    func neverDecreases(seed: Int) {
        var rng = IndexedTrackRNG(seed: UInt64(seed) &+ 70)
        var knots: [TimeWarp.Knot] = []
        var source = rng.uniform() * 10 - 5
        var target = rng.uniform() * 10 - 5
        for _ in 0..<rng.int(1...40) {
            knots.append(.init(source: source, target: target))
            source += 0.001 + rng.uniform() * 5
            target += 0.001 + rng.uniform() * 5
        }
        let warp = TimeWarp(knots: knots)!
        let times = (0..<2000).map { _ in rng.uniform() * 300 - 100 }.sorted()
        var previous = -Double.infinity
        for time in times {
            let mapped = warp.map(time)
            #expect(mapped >= previous)
            previous = mapped
        }
    }
    
    @Test
    func notANumberStaysNotANumber() {
        #expect(TimeWarp.identity.map(.nan).isNaN)
        #expect(TimeWarp(knots: [.init(source: 0, target: 0), .init(source: 1, target: 2)])!.map(.nan).isNaN)
        #expect(TimeWarp.identity.map(.infinity) == .infinity)
        #expect(TimeWarp.identity.map(-.infinity) == -.infinity)
    }
    
    @Test
    func theParametersAreValidOnlyInTheirRanges() {
        #expect(TimeWarp.Parameters.generic.isValid)
        
        var parameters = TimeWarp.Parameters.generic
        parameters.tempoBinCount = 20
        #expect(!parameters.isValid)
        parameters.tempoBinCount = 1
        #expect(!parameters.isValid)
        parameters = .generic
        parameters.tempoBinRatio = 1
        #expect(!parameters.isValid)
        parameters = .generic
        parameters.gapOpen = -1
        #expect(!parameters.isValid)
        parameters = .generic
        parameters.timingNoise = 0
        #expect(!parameters.isValid)
        parameters = .generic
        parameters.maximumSkip = 0
        #expect(!parameters.isValid)
        parameters = .generic
        parameters.maximumExtras = 13
        #expect(!parameters.isValid)
        parameters = .generic
        parameters.fitTolerance = .nan
        #expect(!parameters.isValid)
        parameters = .generic
        parameters.fitTolerance = 0
        parameters.maximumExtras = 0
        #expect(parameters.isValid)
    }
    
    @Test
    func theParametersCanBeSentAcrossConcurrency() async {
        let parameters = TimeWarp.Parameters.generic
        let warp = TimeWarp.identity
        let result = await Task.detached { warp.map(2) + Double(parameters.tempoBinCount) }.value
        #expect(result == 23)
    }
    
    
    // MARK: The events
    
    @Test
    func eventsHoldTheMedianOnsetAndTheKeysOfEachChord() {
        // Chords of one, two, three and four keys, with rolled onsets, and keys at the boundary of the two words.
        let indexed = track([
            note(1, 1.1, 60),
            note(2, 2.1, 21), note(2.01, 2.1, 108),
            note(3, 3.1, 84), note(3.01, 3.1, 85), note(3.03, 3.1, 90),
            note(4, 4.1, 60), note(4.005, 4.1, 64), note(4.01, 4.1, 67), note(4.02, 4.1, 71),
        ])
        let events = TimeWarp.Events(of: indexed)
        let chords = indexed.chords
        #expect(events.count == chords.count)
        for index in 0..<chords.count {
            let chord = chords[index]
            let onsets = (0..<chord.count).map { chord[$0].onset }.sorted()
            let median = onsets.count % 2 == 1 ? onsets[onsets.count / 2] : (onsets[onsets.count / 2 - 1] + onsets[onsets.count / 2]) / 2
            #expect(events.times[index] == median)
            #expect(events.sizes[index] == Float(chord.count))
            var low: UInt64 = 0
            var high: UInt64 = 0
            for position in 0..<chord.count {
                let bit = Int(chord[position].pitch) - 21
                if bit < 64 { low |= 1 << UInt64(bit) } else { high |= 1 << UInt64(bit - 64) }
            }
            #expect(events.low[index] == low)
            #expect(events.high[index] == high)
        }
        // The keys 21 and 84 are the first and the last bit of the low word, and 85 and 108 of the high word.
        #expect(events.low.contains { $0 & 1 != 0 })
        #expect(events.low.contains { $0 >> 63 != 0 })
        #expect(events.high.contains { $0 & 1 != 0 })
        #expect(events.high.contains { $0 >> 23 != 0 })
    }
    
    @Test
    func eventsOfAnEmptyTrackAreEmpty() {
        let events = TimeWarp.Events(of: track([]))
        #expect(events.count == 0)
        #expect(events.times.isEmpty)
    }
    
    
    // MARK: The pilot alignment
    
    @Test(arguments: 0..<25)
    func thePilotAlignmentEqualsAPlainDynamicProgram(seed: Int) {
        let size = 6 + seed % 30
        let (sheet, performance) = randomPiece(seed: UInt64(seed) &+ 300, chords: size, junk: seed % 4)
        let scoring = TimeWarp.Scoring(.generic)
        
        let alignment = TimeWarp.pilot(sheet: sheet, performance: performance, scoring: scoring, halfWidth: 1000)
        let reference = referencePilotScore(sheet: sheet, performance: performance, scoring: scoring)
        #expect(abs(Double(alignment.score) - reference) < 1e-3, "\(alignment.score) against \(reference)")
        
        // The pairs are the alignment that the score says: they are increasing, share keys, and score the same.
        for (previous, next) in zip(alignment.pairs, alignment.pairs.dropFirst()) {
            #expect(previous.sheet < next.sheet && previous.performance < next.performance)
        }
        for pair in alignment.pairs {
            #expect(sheet.sharedCount(Int(pair.sheet), with: performance, Int(pair.performance)) >= 1)
        }
        let counted = pilotPathScore(alignment.pairs, sheet: sheet, performance: performance, scoring: scoring)
        #expect(abs(counted - Double(alignment.score)) < 1e-3, "the pairs score \(counted), not \(alignment.score)")
    }
    
    @Test(arguments: 0..<10)
    func aNarrowBandFindsTheSameAlignmentNearTheDiagonal(seed: Int) {
        // A performance that is the sheet with a few notes changed stays on the diagonal.
        var rng = IndexedTrackRNG(seed: UInt64(seed) &+ 900)
        let keys = (0..<40).map { _ in [rng.int(60...100)] }
        let times = (0..<40).map { Double($0) }
        var changed = keys
        for _ in 0..<4 { changed[rng.int(0...39)] = [rng.int(60...100)] }
        let sheet = events(times: times, keys: keys)
        let performance = events(times: times, keys: changed)
        let scoring = TimeWarp.Scoring(.generic)
        
        let wide = TimeWarp.pilot(sheet: sheet, performance: performance, scoring: scoring, halfWidth: 100)
        let narrow = TimeWarp.pilot(sheet: sheet, performance: performance, scoring: scoring, halfWidth: 4)
        #expect(narrow.score <= wide.score + 1e-4)
        #expect(abs(narrow.score - wide.score) < 1e-4)
        #expect(narrow.pairs.count >= 30)
    }
    
    @Test
    func thePilotAlignmentOfNothingIsNothing() {
        let scoring = TimeWarp.Scoring(.generic)
        let some = events(times: [0, 1, 2], keys: [[60], [62], [64]])
        let none = events(times: [], keys: [])
        #expect(TimeWarp.pilot(sheet: some, performance: none, scoring: scoring).pairs.isEmpty)
        #expect(TimeWarp.pilot(sheet: none, performance: some, scoring: scoring).pairs.isEmpty)
        // No key in common: nothing to pair.
        let other = events(times: [0, 1, 2], keys: [[70], [72], [74]])
        #expect(TimeWarp.pilot(sheet: some, performance: other, scoring: scoring).pairs.isEmpty)
    }
    
    @Test
    func bandCentersFollowThePairs() {
        // Pairs on (sheet, performance): (2, 1), (4, 5), (10, 6).
        let pairs = [TimeWarp.Pair(sheet: 2, performance: 1), .init(sheet: 4, performance: 5), .init(sheet: 10, performance: 6)]
        let centers = TimeWarp.bandCenters(pairs: pairs, sheetCount: 12, performanceCount: 9)
        #expect(centers.count == 9)
        #expect(centers[1] == 2)
        #expect(centers[5] == 4)
        #expect(centers[6] == 10)
        #expect(centers[0] == 1) // one chord of the sheet for each chord of the performance before the first pair
        #expect(centers[3] == 3) // halfway between the first two pairs
        #expect(centers[8] == 11) // after the last pair, clamped to the sheet
        #expect(zip(centers, centers.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(centers.allSatisfy { $0 >= 0 && $0 <= 11 })
        
        // Without two pairs, the diagonal.
        let diagonal = TimeWarp.bandCenters(pairs: [], sheetCount: 11, performanceCount: 6)
        #expect(diagonal == [0, 2, 4, 6, 8, 10])
    }
    
    
    // MARK: The tempo search
    
    @Test(arguments: 0..<12)
    func theTempoSearchEqualsAPlainDynamicProgram(seed: Int) {
        let testCase = TempoCase.generic(seed: seed)
        let (sheet, performance, parameters, rate) = (testCase.sheet, testCase.performance, testCase.parameters, testCase.rate)
        let costs = TimeWarp.TempoCosts(parameters)
        
        // A band that covers every chord of the sheet, whatever the centers.
        let centers = [Int32](repeating: 0, count: performance.count)
        let alignment = TimeWarp.tempoPass(sheet: sheet, performance: performance, rate: rate, costs: costs, halfWidth: sheet.count, centers: centers)
        let reference = referenceTempoScore(sheet: sheet, performance: performance, rate: rate, parameters: parameters)
        #expect(abs(Double(alignment.score) - reference) < 0.02, "\(alignment.score) against \(reference)")
        #expect(!alignment.touchedEdge)
        
        // The pairs are a path: the performance advances, the sheet never goes back, the chords share keys, and the best tempo states along the pairs score what the search says.
        #expect(!alignment.pairs.isEmpty)
        for (previous, next) in zip(alignment.pairs, alignment.pairs.dropFirst()) {
            #expect(previous.performance < next.performance && previous.sheet <= next.sheet)
        }
        for pair in alignment.pairs {
            #expect(sheet.sharedCount(Int(pair.sheet), with: performance, Int(pair.performance)) >= 1)
        }
        let counted = tempoPathScore(alignment.pairs, sheet: sheet, performance: performance, rate: rate, parameters: parameters)
        #expect(abs(counted - Double(alignment.score)) < 0.02, "the pairs score \(counted), not \(alignment.score)")
    }
    
    @Test(arguments: 0..<4)
    func theTempoSearchEqualsAPlainDynamicProgramWithOtherConstants(seed: Int) {
        let testCase = TempoCase.otherConstants(seed: seed)
        let (sheet, performance, parameters, rate) = (testCase.sheet, testCase.performance, testCase.parameters, testCase.rate)
        
        let centers = [Int32](repeating: 0, count: performance.count)
        let alignment = TimeWarp.tempoPass(sheet: sheet, performance: performance, rate: rate, costs: TimeWarp.TempoCosts(parameters), halfWidth: sheet.count, centers: centers)
        let reference = referenceTempoScore(sheet: sheet, performance: performance, rate: rate, parameters: parameters)
        #expect(abs(Double(alignment.score) - reference) < 0.02, "\(alignment.score) against \(reference)")
        let counted = tempoPathScore(alignment.pairs, sheet: sheet, performance: performance, rate: rate, parameters: parameters)
        #expect(abs(counted - Double(alignment.score)) < 0.02, "the pairs score \(counted), not \(alignment.score)")
    }
    
    /// The reference tests are only as good as the pieces they run on: between them, the best paths take every way of arriving that the search has.
    @Test(.tags(.evolution), .evolution)
    func theRandomPiecesTakeEveryWayOfArriving() {
        var total = WaysOfArriving()
        let cases = (0..<12).map { TempoCase.generic(seed: $0) } + (0..<4).map { TempoCase.otherConstants(seed: $0) }
        for testCase in cases {
            let centers = [Int32](repeating: 0, count: testCase.performance.count)
            let alignment = TimeWarp.tempoPass(sheet: testCase.sheet, performance: testCase.performance, rate: testCase.rate, costs: TimeWarp.TempoCosts(testCase.parameters), halfWidth: testCase.sheet.count, centers: centers)
            total = total + WaysOfArriving(alignment.pairs, parameters: testCase.parameters)
        }
        print("[TimeWarp] ways of arriving in the random reference pieces: \(total.description)")
        #expect(total.plain > 0 && total.extras > 0 && total.skips > 0 && total.splits > 0 && total.restarts > 0)
    }
    
    /// The search steps over foreign chords and left out chords with a restart, and plays a chord that is rolled into two with a split, as the plain dynamic program does.
    @Test(arguments: 0..<8)
    func theTempoSearchCrossesForeignMaterialAndRolledChords(seed: Int) {
        let (sheet, performance) = directedPiece(seed: UInt64(seed) &+ 1100)
        let parameters = TimeWarp.Parameters.generic
        let rate = (performance.times.last! - performance.times.first!) / (sheet.times.last! - sheet.times.first!)
        
        let centers = [Int32](repeating: 0, count: performance.count)
        let alignment = TimeWarp.tempoPass(sheet: sheet, performance: performance, rate: rate, costs: TimeWarp.TempoCosts(parameters), halfWidth: sheet.count, centers: centers)
        let reference = referenceTempoScore(sheet: sheet, performance: performance, rate: rate, parameters: parameters)
        #expect(abs(Double(alignment.score) - reference) < 0.03, "\(alignment.score) against \(reference)")
        let counted = tempoPathScore(alignment.pairs, sheet: sheet, performance: performance, rate: rate, parameters: parameters)
        #expect(abs(counted - Double(alignment.score)) < 0.03, "the pairs score \(counted), not \(alignment.score)")
    }
    
    @Test(.tags(.evolution), .evolution)
    func theDirectedPiecesTakeRestartsAndSplits() {
        var total = WaysOfArriving()
        for seed in 0..<8 {
            let (sheet, performance) = directedPiece(seed: UInt64(seed) &+ 1100)
            let rate = (performance.times.last! - performance.times.first!) / (sheet.times.last! - sheet.times.first!)
            let centers = [Int32](repeating: 0, count: performance.count)
            let alignment = TimeWarp.tempoPass(sheet: sheet, performance: performance, rate: rate, costs: TimeWarp.TempoCosts(.generic), halfWidth: sheet.count, centers: centers)
            total = total + WaysOfArriving(alignment.pairs, parameters: .generic)
        }
        print("[TimeWarp] ways of arriving in the directed reference pieces: \(total.description)")
        #expect(total.restarts >= 8 && total.splits >= 8)
    }
    
    /// The search keeps what it needs to trace the path back for the cells that have states alone, so it has to know which those are before it starts.
    @Test(arguments: [1, 4, 16, 100])
    func theRowsOfTheBandStartWhereTheCellsThatHaveStatesAre(halfWidth: Int) {
        let (sheet, performance) = randomPiece(seed: 61, chords: 60, junk: 3, keys: 60...100)
        // Centers that move through the sheet, so that the band is clipped at both ends.
        let centers = (0..<performance.count).map { Int32(Swift.min(sheet.count - 1, $0 * sheet.count / performance.count)) }
        let starts = TimeWarp.tempoRowStarts(sheet: sheet, performance: performance, halfWidth: halfWidth, centers: centers)
        #expect(starts.count == performance.count + 1)
        
        var expected = 0
        for j in 0..<performance.count {
            #expect(starts[j] == expected)
            for i in Swift.max(0, Int(centers[j]) - halfWidth)...Swift.min(sheet.count - 1, Int(centers[j]) + halfWidth) where sheet.sharedCount(i, with: performance, j) >= 1 {
                expected += 1
            }
        }
        #expect(starts[performance.count] == expected)
    }
    
    @Test
    func theTempoSearchWidensABandThatIsTooNarrow() {
        let parameters = TimeWarp.Parameters.generic
        let (sheet, performance) = randomPiece(seed: 42, chords: 40, junk: 0, keys: 60...100)
        let rate = (performance.times.last! - performance.times.first!) / (sheet.times.last! - sheet.times.first!)
        let costs = TimeWarp.TempoCosts(parameters)
        let wrongCenters = [Int32](repeating: 0, count: performance.count)
        
        let narrow = TimeWarp.tempoPass(sheet: sheet, performance: performance, rate: rate, costs: costs, halfWidth: 2, centers: wrongCenters)
        #expect(narrow.touchedEdge)
        let widened = TimeWarp.tempoSearch(sheet: sheet, performance: performance, rate: rate, costs: costs, centers: wrongCenters, halfWidth: 2)
        let full = TimeWarp.tempoPass(sheet: sheet, performance: performance, rate: rate, costs: costs, halfWidth: sheet.count, centers: wrongCenters)
        #expect(abs(widened.score - full.score) < 1e-3)
        #expect(widened.score > narrow.score)
    }
    
    
    // MARK: The fit
    
    @Test
    func theFitMergesAnchorsAtOneTimeByTheirWeights() throws {
        let anchors = [
            TimeWarp.Anchor(source: 0, target: 0, weight: 1),
            TimeWarp.Anchor(source: 2, target: 3, weight: 1),
            TimeWarp.Anchor(source: 2, target: 5, weight: 3),
            TimeWarp.Anchor(source: 4, target: 8, weight: 1),
        ]
        let warp = try #require(TimeWarp.fit(anchors, tolerance: 0))
        #expect(warp.knots.map(\.source) == [0, 2, 4])
        #expect(warp.knots[1].target == 4.5) // (3 * 1 + 5 * 3) / 4
    }
    
    @Test
    func theFitRepairsTheOrderOfTheTargets() throws {
        // The targets 5 then 3 go the wrong way, so they pool to their weighted mean.
        let anchors = [
            TimeWarp.Anchor(source: 0, target: 0, weight: 1),
            TimeWarp.Anchor(source: 1, target: 5, weight: 1),
            TimeWarp.Anchor(source: 2, target: 3, weight: 1),
            TimeWarp.Anchor(source: 3, target: 10, weight: 1),
        ]
        let warp = try #require(TimeWarp.fit(anchors, tolerance: 0))
        #expect(warp.knots.count == 4)
        #expect(abs(warp.knots[1].target - 4) < 0.05)
        #expect(abs(warp.knots[2].target - 4) < 0.05)
        #expect(zip(warp.knots, warp.knots.dropFirst()).allSatisfy { $0.target < $1.target })
    }
    
    @Test(arguments: 0..<10)
    func theFitIsAlwaysAValidWarpThatStaysWithinTheTolerance(seed: Int) throws {
        var rng = IndexedTrackRNG(seed: UInt64(seed) &+ 40)
        var source = 0.0
        var anchors: [TimeWarp.Anchor] = []
        for _ in 0..<300 {
            source += rng.uniform() < 0.1 ? 0 : 0.2 + rng.uniform()
            // A tempo of 1.3 with noise, and some wild pairs.
            let wild = rng.uniform() < 0.05
            anchors.append(.init(source: source, target: 1.3 * source + (wild ? rng.gaussian() * 5 : rng.gaussian() * 0.01), weight: 0.2 + rng.uniform()))
        }
        let exact = try #require(TimeWarp.fit(anchors, tolerance: 0))
        let tolerance = 0.05
        let simplified = try #require(TimeWarp.fit(anchors, tolerance: tolerance))
        #expect(simplified.knots.count < exact.knots.count)
        // The simplified warp stays within the tolerance of the exact fit at every knot of it.
        for knot in exact.knots {
            #expect(abs(simplified.map(knot.source) - knot.target) <= tolerance + 1e-9)
        }
        #expect(TimeWarp(knots: simplified.knots) != nil)
    }
    
    @Test
    func theFitNeedsTwoDistinctSourceTimes() {
        #expect(TimeWarp.fit([], tolerance: 0.1) == nil)
        #expect(TimeWarp.fit([.init(source: 1, target: 2, weight: 1)], tolerance: 0.1) == nil)
        #expect(TimeWarp.fit([.init(source: 1, target: 2, weight: 1), .init(source: 1, target: 3, weight: 1)], tolerance: 0.1) == nil)
        #expect(TimeWarp.fit([.init(source: 1, target: 2, weight: 1), .init(source: 2, target: 3, weight: 1)], tolerance: 0.1) != nil)
    }
    
    @Test
    func theFitSortsAnchorsThatAreOutOfOrder() throws {
        let anchors = [
            TimeWarp.Anchor(source: 3, target: 6, weight: 1),
            TimeWarp.Anchor(source: 1, target: 2, weight: 1),
            TimeWarp.Anchor(source: 2, target: 4, weight: 1),
        ]
        let warp = try #require(TimeWarp.fit(anchors, tolerance: 0))
        #expect(warp.knots.map(\.source) == [1, 2, 3])
        #expect(warp.knots.map(\.target) == [2, 4, 6])
    }
    
    
    // MARK: Recovery
    
    /// A known tempo curve is recovered from a sheet and a performance made from it, at the chords of the sheet.
    @Test(.tags(.evolution), .evolution, arguments: recoveryScenarios)
    fileprivate func recoversTheTempoCurve(scenario: Scenario) {
        var errors: [Double] = []
        for (index, chords) in [250, 500, 800].enumerated() {
            var scenario = scenario
            scenario.seed = UInt64(1000 + index)
            let sheetNotes = toySheet(chords: chords, seed: UInt64(5 + index))
            let (performanceNotes, truth) = realize(scenario, sheet: sheetNotes)
            let sheet = track(sheetNotes)
            let warp = sheet.timeWarp(to: track(performanceNotes))
            errors += TimeWarp.Events(of: sheet).times.map { abs(warp.map($0) - truth($0)) }
        }
        report(scenario.name, errors: errors, tolerance: scenario.tolerance)
        #expect(percentile(errors, 0.95) <= scenario.tolerance, "the 95th percentile of the error is \(percentile(errors, 0.95)) beats")
        #expect(percentile(errors, 0.5) <= scenario.tolerance / 3)
    }
    
    /// Unrelated music before and after the piece in the performance does not matter.
    @Test(.tags(.evolution), .evolution)
    func ignoresMusicBeforeAndAfterThePiece() {
        var scenario = Scenario(name: "extra music", ratio: 1.15, randomWarp: 0.25, jitter: 0.03, missing: 0.03, extra: 0.03, tolerance: 0.12)
        scenario.junkChords = 80
        var errors: [Double] = []
        for (index, chords) in [300, 600].enumerated() {
            scenario.seed = UInt64(2000 + index)
            let sheetNotes = toySheet(chords: chords, seed: UInt64(15 + index))
            let (performanceNotes, truth) = realize(scenario, sheet: sheetNotes)
            let sheet = track(sheetNotes)
            let warp = sheet.timeWarp(to: track(performanceNotes))
            errors += TimeWarp.Events(of: sheet).times.map { abs(warp.map($0) - truth($0)) }
        }
        report(scenario.name, errors: errors, tolerance: scenario.tolerance)
        #expect(percentile(errors, 0.95) <= scenario.tolerance, "the 95th percentile of the error is \(percentile(errors, 0.95)) beats")
    }
    
    /// A sheet warped by a known function, which `timeWarp(to:)` has to give back: the performance has the same notes, so only the fit is off.
    @Test(.tags(.evolution), .evolution, arguments: 0..<3)
    func recoversTheWarpThatMadeTheTrack(seed: Int) {
        let sheetNotes = toySheet(chords: 400, seed: UInt64(30 + seed))
        var scenario = Scenario(name: "equivariance", ratio: 1.2, drift: 0.3, randomWarp: 0.3)
        scenario.seed = UInt64(60 + seed)
        let (_, truth) = realize(scenario, sheet: sheetNotes)
        let end = (sheetNotes.map(\.onset).max() ?? 1) + 1
        let known = truth.warp(until: end, every: 0.5)
        
        let sheet = track(sheetNotes)
        let performance = sheet.warped(by: known)
        let recovered = sheet.timeWarp(to: performance)
        
        let errors = TimeWarp.Events(of: sheet).times.map { abs(recovered.map($0) - known.map($0)) }
        report("recovers the warp that made the track (\(seed))", errors: errors, tolerance: 0.03)
        #expect(percentile(errors, 0.95) <= 0.03)
        #expect((errors.max() ?? 0) <= 0.1)
    }
    
    @Test
    func aTrackWarpedToItselfIsTheIdentity() {
        let sheet = track(toySheet(chords: 300, seed: 77))
        let warp = sheet.timeWarp(to: sheet)
        let errors = TimeWarp.Events(of: sheet).times.map { abs(warp.map($0) - $0) }
        #expect((errors.max() ?? 0) <= TimeWarp.Parameters.generic.fitTolerance + 1e-9)
    }
    
    @Test
    func theWarpDoesNotChangeBetweenRuns() {
        let sheetNotes = toySheet(chords: 200, seed: 8)
        let (performanceNotes, _) = realize(Scenario(name: "repeat", ratio: 1.3, randomWarp: 0.2, jitter: 0.02, missing: 0.05, extra: 0.05), sheet: sheetNotes)
        let sheet = track(sheetNotes)
        let performance = track(performanceNotes)
        #expect(sheet.timeWarp(to: performance) == sheet.timeWarp(to: performance))
    }
    
    @Test
    func aLargerFitToleranceGivesFewerKnots() {
        let sheetNotes = toySheet(chords: 400, seed: 9)
        let (performanceNotes, _) = realize(Scenario(name: "tolerance", ratio: 1.1, randomWarp: 0.3, jitter: 0.02), sheet: sheetNotes)
        let sheet = track(sheetNotes)
        let performance = track(performanceNotes)
        var tight = TimeWarp.Parameters.generic
        tight.fitTolerance = 0.005
        var loose = TimeWarp.Parameters.generic
        loose.fitTolerance = 0.2
        let tightWarp = sheet.timeWarp(to: performance, parameters: tight)
        let looseWarp = sheet.timeWarp(to: performance, parameters: loose)
        #expect(looseWarp.knots.count < tightWarp.knots.count)
        #expect(looseWarp.knots.count >= 2)
    }
    
    @Test
    func theGenericParametersRecoverACleanWarp() {
        let sheetNotes = toySheet(chords: 300, seed: 12)
        let (performanceNotes, truth) = realize(Scenario(name: "presets", ratio: 1.25, drift: 0.2), sheet: sheetNotes)
        let sheet = track(sheetNotes)
        let performance = track(performanceNotes)
        let warp = sheet.timeWarp(to: performance, parameters: .generic)
        let errors = TimeWarp.Events(of: sheet).times.map { abs(warp.map($0) - truth($0)) }
        #expect(percentile(errors, 0.95) <= 0.03)
    }
    
    /// A long piece in the time of a test: 2,000 chords against 2,200.
    @Test(.tags(.evolution), .evolution)
    func aLongPieceTakesSeconds() {
        let sheetNotes = toySheet(chords: 2000, seed: 21)
        let (performanceNotes, truth) = realize(Scenario(name: "long", ratio: 1.2, randomWarp: 0.3, jitter: 0.03, missing: 0.05, extra: 0.05), sheet: sheetNotes)
        let sheet = track(sheetNotes)
        let performance = track(performanceNotes)
        _ = sheet.chords
        _ = performance.chords
        
        let start = Date()
        let warp = sheet.timeWarp(to: performance)
        let seconds = Date().timeIntervalSince(start)
        let errors = TimeWarp.Events(of: sheet).times.map { abs(warp.map($0) - truth($0)) }
        report("long piece in \(String(format: "%.2f", seconds)) s", errors: errors, tolerance: 0.1)
        #expect(percentile(errors, 0.95) <= 0.1)
    }
    
    
    // MARK: Degenerate tracks
    
    @Test
    func emptyTracksGiveTheIdentity() {
        let something = track(toySheet(chords: 20, seed: 1))
        #expect(track([]).timeWarp(to: something) == .identity)
        #expect(something.timeWarp(to: track([])) == .identity)
        #expect(track([]).timeWarp(to: track([])) == .identity)
    }
    
    @Test
    func aTrackWithAllChordsAtOneTimeIsShifted() {
        let one = track([note(2, 3, 60)])
        let many = track(toySheet(chords: 30, seed: 3))
        let firstOfMany = TimeWarp.Events(of: many).times[0]
        
        let toMany = one.timeWarp(to: many)
        #expect(toMany.map(2) == firstOfMany)
        #expect(toMany.map(5) == firstOfMany + 3)
        
        let fromMany = many.timeWarp(to: one)
        #expect(fromMany.map(firstOfMany) == 2)
        #expect(one.timeWarp(to: track([note(10, 11, 62)])).map(2) == 10)
    }
    
    @Test
    func fewChordsGiveTheLineThroughTheFirstAndLast() {
        let sheet = track([note(0, 0.1, 60), note(1, 1.1, 62), note(2, 2.1, 64), note(4, 4.1, 65)])
        let performance = track([note(10, 10.1, 60), note(12, 12.1, 62), note(13, 13.1, 64), note(18, 18.1, 65)])
        let warp = sheet.timeWarp(to: performance)
        #expect(warp.knots.count == 2)
        #expect(warp.map(0) == 10)
        #expect(warp.map(4) == 18)
        #expect(warp.map(2) == 14)
    }
    
    @Test
    func tracksWithNoKeyInCommonStillGiveAValidWarp() {
        let sheet = track((0..<40).map { note(Double($0), Double($0) + 0.1, 40 + UInt8($0 % 8)) })
        let performance = track((0..<40).map { note(5 + 1.5 * Double($0), 5.1 + 1.5 * Double($0), 90 + UInt8($0 % 8)) })
        let warp = sheet.timeWarp(to: performance)
        #expect(TimeWarp(knots: warp.knots) != nil)
        // Without a pair to go by, the line through the first and the last chord.
        #expect(warp.map(0) == 5)
        #expect(warp.map(39) == 5 + 1.5 * 39)
    }
    
    @Test
    func aSheetWithRepeatedFiguresIsNotConfusedForOneOfItsRepeats() {
        // A figure played four times, as a sheet; the performance plays it once, slower, and then continues.
        let figure: [UInt8] = [60, 64, 67, 72, 67, 64, 62, 65, 69, 74, 69, 65]
        var sheetNotes: [MIDINote] = []
        var time = 0.0
        for repeatIndex in 0..<4 {
            for (index, pitch) in figure.enumerated() {
                sheetNotes.append(note(time, time + 0.1, pitch + (repeatIndex == 3 ? 1 : 0)))
                time += 0.5 + (index % 3 == 0 ? 0.25 : 0)
            }
        }
        var performanceNotes: [MIDINote] = []
        for note_ in sheetNotes {
            performanceNotes.append(note(4 + 1.3 * note_.onset, 4.1 + 1.3 * note_.onset, note_.pitch))
        }
        let sheet = track(sheetNotes)
        let warp = sheet.timeWarp(to: track(performanceNotes))
        let errors = TimeWarp.Events(of: sheet).times.map { abs(warp.map($0) - (4 + 1.3 * $0)) }
        #expect((errors.max() ?? 0) <= 0.05, "the largest error is \(errors.max() ?? 0)")
    }
    
    
    // MARK: Applying a warp
    
    @Test
    func warpedMapsEveryTimeOfTheTrack() throws {
        var track = MIDITrack(
            notes: [note(1, 2, 60, velocity: 70), note(3, 4.5, 62, velocity: 90)],
            sustains: [MIDISustainEvent(onset: 0.5, offset: 2.5), MIDISustainEvent(onset: 3, offset: 5)],
            metaEvents: [MIDIMetaEvent(timestamp: 1.5, type: 0x06, data: Data("marker".utf8))],
            channelEvents: MIDIChannelEvents([MIDIChannelEvent(onset: 2, channel: 1, message: .controlChange(controller: 7, value: 64)), MIDIChannelEvent(onset: 4, channel: 1, message: .programChange(program: 3))])
        )
        track.rawData = [MIDIKit.MIDIRawData(timestamp: 2.5, data: Data([0xF0, 0x7E, 0x7F, 0x09, 0x01, 0xF7]))]
        let container = MIDIContainer(tracks: [track])
        let indexed = IndexedTrack(container)
        let warp = try #require(TimeWarp(knots: [.init(source: 0, target: 1), .init(source: 2, target: 5), .init(source: 6, target: 7)]))
        let warped = indexed.warped(by: warp)
        
        #expect(warped.notes.count == indexed.notes.count)
        for (before, after) in zip(indexed.notes, warped.notes) {
            #expect(after.onset == warp.map(before.onset))
            #expect(after.offset == warp.map(before.offset))
            #expect(after.pitch == before.pitch && after.velocity == before.velocity && after.channel == before.channel)
        }
        #expect(warped.sustains.contents.map(\.onset) == indexed.sustains.contents.map { warp.map($0.onset) })
        #expect(warped.sustains.contents.map(\.offset) == indexed.sustains.contents.map { warp.map($0.offset) })
        #expect(warped.channelEvents.map(\.onset) == indexed.channelEvents.map { warp.map($0.onset) })
        #expect(warped.channelEvents.map(\.message) == indexed.channelEvents.map(\.message))
        #expect(warped.rawData.map(\.timestamp) == indexed.rawData.map { warp.map($0.timestamp) })
        #expect(warped.rawData.map(\.data) == indexed.rawData.map(\.data))
        #expect(!indexed.rawData.isEmpty)
        #expect(warped.metaEvents.map(\.timestamp) == indexed.metaEvents.map { warp.map($0.timestamp) })
        #expect(!indexed.metaEvents.isEmpty)
        #expect(warped.metaEvents.map(\.data) == indexed.metaEvents.map(\.data))
    }
    
    @Test
    func warpedKeepsTheProfile() {
        let indexed = IndexedTrack(MIDIContainer(tracks: [MIDITrack(notes: [note(0, 1, 60), note(1, 2, 62)])]), profile: TaggedProfile())
        let warped = indexed.warped(by: TimeWarp(knots: [.init(source: 0, target: 3), .init(source: 5, target: 8)])!)
        #expect(warped.profile is TaggedProfile)
        #expect(warped.notes.map(\.onset) == [3, 4])
        #expect(IndexedTrack(MIDIContainer(tracks: [MIDITrack(notes: [note(0, 1, 60)])])).warped(by: .identity).profile is GenericProfile)
    }
    
    @Test(arguments: 0..<10)
    func warpedByTheIdentityChangesNothing(seed: Int) {
        let indexed = track(cleanInput(seed: UInt64(seed) &+ 400, count: 200), sustains: [MIDISustainEvent(onset: 1, offset: 3), MIDISustainEvent(onset: 5, offset: 9)])
        let warped = indexed.warped(by: .identity)
        #expect(warped.notes == indexed.notes)
        #expect(warped.sustains == indexed.sustains)
    }
    
    @Test(arguments: 0..<10)
    func warpedKeepsTheOrderAndTheInvariantsWhenTheWarpSpeedsUp(seed: Int) {
        let indexed = track(cleanInput(seed: UInt64(seed) &+ 500, count: 300))
        var rng = IndexedTrackRNG(seed: UInt64(seed))
        // Slopes of at least 1 never bring two notes closer.
        var knots: [TimeWarp.Knot] = []
        var source = 0.0
        var target = 3.0
        for _ in 0..<30 {
            knots.append(.init(source: source, target: target))
            let step = 1 + rng.uniform() * 4
            source += step
            target += step * (1 + rng.uniform() * 2)
        }
        let warp = TimeWarp(knots: knots)!
        let warped = indexed.warped(by: warp)
        #expect(warped.notes.map(\.pitch) == indexed.notes.map(\.pitch))
        #expect(zip(warped.notes, warped.notes.dropFirst()).allSatisfy { $0.onset <= $1.onset })
        #expect(IndexedTrack.isValid(notes: warped.notes, lanes: warped.lanes))
    }
    
    @Test
    func warpedRestoresTheInvariantsWhenTheWarpSlowsDown() {
        // A key struck every half beat, which a warp that is a hundredth as fast brings closer than the minimum gap.
        let notes = (0..<40).map { note(Double($0) * 0.5, Double($0) * 0.5 + 0.1, 60) } + (0..<40).map { note(Double($0) * 0.5, Double($0) * 0.5 + 0.2, 64) }
        let indexed = track(notes)
        let warp = TimeWarp(knots: [.init(source: 0, target: 0), .init(source: 100, target: 1)])!
        let warped = indexed.warped(by: warp)
        #expect(warped.notes.count < indexed.notes.count)
        #expect(!warped.notes.isEmpty)
        #expect(IndexedTrack.isValid(notes: warped.notes, lanes: warped.lanes))
        #expect(zip(warped.notes, warped.notes.dropFirst()).allSatisfy { isOrdered($0, $1) })
    }
    
    @Test
    func warpedOfAnEmptyTrackIsEmpty() {
        let warped = track([]).warped(by: TimeWarp(knots: [.init(source: 0, target: 1), .init(source: 1, target: 3)])!)
        #expect(warped.notes.isEmpty)
        #expect(warped.sustains.isEmpty)
    }
    
    @Test
    func aSheetWarpedByItsWarpLandsOnThePerformance() {
        let sheetNotes = toySheet(chords: 300, seed: 14)
        let (performanceNotes, _) = realize(Scenario(name: "landing", ratio: 1.3, randomWarp: 0.25, jitter: 0.015, missing: 0.03, extra: 0.03), sheet: sheetNotes)
        let sheet = track(sheetNotes)
        let performance = track(performanceNotes)
        let aligned = sheet.warped(by: sheet.timeWarp(to: performance))
        
        // The first and the last chord of the aligned sheet are where they are in the performance, give or take a roll.
        let alignedTimes = TimeWarp.Events(of: aligned).times
        let performanceTimes = TimeWarp.Events(of: performance).times
        #expect(abs(alignedTimes[0] - performanceTimes[0]) < 0.5)
        #expect(abs(alignedTimes[alignedTimes.count - 1] - performanceTimes[performanceTimes.count - 1]) < 0.5)
        #expect(zip(aligned.notes, aligned.notes.dropFirst()).allSatisfy { isOrdered($0, $1) })
    }
    
}
