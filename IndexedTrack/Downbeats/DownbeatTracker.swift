//
//  DownbeatTracker.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import Foundation
import Accelerate
import MIDIKit


/// Finds the downbeats of a performance by following the tempo and the position in the bar together.
///
/// The tracker decodes a bar pointer: at every frame of 0.04 beat, the state is the number of beats in the bar (2, 3 or 4), the length of a beat (0.4 to 2.8 beats at 120 BPM, in 32 steps), and the position in the bar. The pointer moves on by one frame each frame. The beat length may change only where a beat starts, at a cost that grows with the size of the change, and the number of beats in a bar only where a bar starts.
///
/// Two kinds of evidence score the path:
///
/// - The **onset envelope**: frames where a beat starts should have notes, frames between beats should not.
/// - The **downbeat cue** at each chord, a weighted sum of seven cues, each normalized over the piece: how low the **bass** is, the **mass** of the notes struck (their velocities), how long they **ring** (with the pedal), how much the pitch classes **change** across the chord over one and over two beats, whether the **pedal** is pressed again right after, and the **gap** before the chord. The cue adds to the frames where a bar starts.
///
/// Decoding the tempo and the bar together lets each correct the other: a beat that the notes place badly is put right by the bar it belongs to. A tracker that commits to beats first, or to a bar length first, cannot do that.
///
/// The constants of ``generic``, ``transkun`` and ``pianoTranscription`` were tuned on the performances of the ASAP dataset, as captured by the Disklavier and as transcribed from the MAESTRO audio, against ASAP's downbeat annotations, maximizing the downbeat F-measure within ±70 ms. On held-out pieces, ``generic`` found 0.44 of the downbeats of transkun transcriptions and ``transkun`` 0.45 (F-measure), against 0.28 for the downbeat finder of earlier versions of MIDIKit.
public struct DownbeatTracker: Sendable, Hashable {

    /// The weight of how low the lowest note of a chord is.
    public var bassWeight: Double

    /// The weight of the mass of a chord: the sum of its velocities.
    public var massWeight: Double

    /// The weight of how long the notes of a chord ring, held by the pedal. It has no effect unless ``readsOffsets`` is `true`.
    public var durationWeight: Double

    /// The weight of how much the pitch classes change across a chord, over one beat on each side.
    public var chromaWeight: Double

    /// The weight of how much the pitch classes change across a chord, over two beats on each side.
    public var wideChromaWeight: Double

    /// The weight of the pedal being pressed within half a beat after a chord.
    public var pedalWeight: Double

    /// The weight of the gap before a chord, in beats, up to two.
    public var gapWeight: Double

    /// Whether the offsets of the notes are reliable enough to read.
    ///
    /// When `false`, the tracker never reads a note offset: every note counts as half a beat long, the duration cue is `0`, and the end of the piece is taken from the onsets and the sustains.
    ///
    /// The tracker also reads the onsets of ``IndexedTrack/chords``, which the profile forms. The glissando check that every ``ChordArbiter`` shares looks at how long notes last, so a chord can still depend on the offsets.
    public var readsOffsets: Bool

    /// The cost of changing the length of a beat, per unit of the absolute log ratio of the two lengths.
    public var tempoChangeCost: Double

    /// The floor added to the onset envelope before its logarithm is taken, which bounds the cost of a beat without notes.
    public var beatFloor: Double

    /// How much an onset between beats counts against the path, from `0` (not at all) to `1`.
    public var offBeatWeight: Double

    /// The gain of the downbeat cue on the frames where a bar starts.
    public var downbeatGain: Double

    /// The cost of every bar, which keeps the bars from becoming too short.
    public var downbeatCost: Double

    /// The cost of changing the number of beats in a bar.
    public var meterChangeCost: Double

    /// The part of a beat, from its start, where notes are expected: the length of the beat divided by this value.
    public var beatRegionDivisor: Double

    /// A bonus for every bar of three beats.
    public var tripleMeterBonus: Double

    /// A bonus for every bar of four beats.
    public var quadrupleMeterBonus: Double


    /// The tracker that assumes nothing about where the notes came from, apart from offsets that can be read.
    ///
    /// Tuned on the Disklavier performances and on their transkun and PianoTranscription transcriptions together.
    public static let generic = DownbeatTracker(
        bassWeight: 1.6,
        massWeight: 0.3,
        durationWeight: 1.1,
        chromaWeight: 1,
        wideChromaWeight: 0.6,
        pedalWeight: 0.5,
        gapWeight: 0.3,
        readsOffsets: true,
        tempoChangeCost: 30,
        beatFloor: 0.028,
        offBeatWeight: 0.6,
        downbeatGain: 1.6,
        downbeatCost: 0.7,
        meterChangeCost: 8,
        beatRegionDivisor: 20,
        tripleMeterBonus: 0.4,
        quadrupleMeterBonus: 0.8
    )


    /// Creates a tracker with the given parameters.
    ///
    /// See the properties of the same names for what each parameter does.
    public init(
        bassWeight: Double,
        massWeight: Double,
        durationWeight: Double,
        chromaWeight: Double,
        wideChromaWeight: Double,
        pedalWeight: Double,
        gapWeight: Double,
        readsOffsets: Bool,
        tempoChangeCost: Double,
        beatFloor: Double,
        offBeatWeight: Double,
        downbeatGain: Double,
        downbeatCost: Double,
        meterChangeCost: Double,
        beatRegionDivisor: Double,
        tripleMeterBonus: Double,
        quadrupleMeterBonus: Double
    ) {
        self.bassWeight = bassWeight
        self.massWeight = massWeight
        self.durationWeight = durationWeight
        self.chromaWeight = chromaWeight
        self.wideChromaWeight = wideChromaWeight
        self.pedalWeight = pedalWeight
        self.gapWeight = gapWeight
        self.readsOffsets = readsOffsets
        self.tempoChangeCost = tempoChangeCost
        self.beatFloor = beatFloor
        self.offBeatWeight = offBeatWeight
        self.downbeatGain = downbeatGain
        self.downbeatCost = downbeatCost
        self.meterChangeCost = meterChangeCost
        self.beatRegionDivisor = beatRegionDivisor
        self.tripleMeterBonus = tripleMeterBonus
        self.quadrupleMeterBonus = quadrupleMeterBonus
    }


    // MARK: - Structure

    /// The length of a frame, in beats.
    static let hop: Double = 0.04

    /// The shortest beat, in beats.
    static let minimumBeat: Double = 0.4

    /// The longest beat, in beats.
    static let maximumBeat: Double = 2.8

    /// The number of beat lengths, spaced evenly on a log scale.
    static let beatLengthCount = 32

    /// How many beat lengths up or down the beat may change at once.
    static let maximumBeatLengthStep = 4

    /// The numbers of beats in a bar.
    static let meters = [2, 3, 4]


    /// Finds the downbeats of `track`.
    ///
    /// Every anchor in `prior` is a downbeat of the result, at its exact time: the decoding is forced to start a bar at the frame of each anchor. An anchor less than two of the shortest beats after the previous forced one is kept in the result but does not force the decoding. Anchors that are not finite or are negative are ignored.
    ///
    /// - Parameters:
    ///   - track: The track whose downbeats are found.
    ///   - prior: Times, in beats, that are known to be downbeats.
    ///
    /// - Returns: Strictly increasing downbeats, in beats at 120 BPM. Empty, apart from `prior`, when `track` has no notes.
    ///
    /// - Complexity: O(*f* · *s*) time and O(*f* · *b*) memory, where *f* is the number of frames (25 per beat), *s* the number of states (about 9,300) and *b* the number of states where a beat starts (about 280), in addition to forming the ``IndexedTrack/chords`` on first use. A piece of 20 minutes at 120 BPM takes about 70 MB.
    public func downbeats(in track: IndexedTrack, prior: [Double] = []) -> [Double] {
        let anchors = Self.sanitized(prior)
        let notes = track.notes
        guard !notes.isEmpty else { return anchors }

        let hop = Self.hop
        let cues = DownbeatCues(track: track, readsOffsets: self.readsOffsets)
        var end = notes[notes.count &- 1].onset + 1
        if self.readsOffsets {
            end = 0
            for note in notes { end = Swift.max(end, note.offset) }
        }
        for sustain in track.sustains { end = Swift.max(end, sustain.offset) }

        // MARK: Evidence per frame

        var envelope = cues.onsetEnvelope(frames: Swift.max(Int((end / hop).rounded(.up)) &+ 4, 8), hop: hop)
        let frameCount = envelope.count
        var floorValues: [Double] = []
        for value in envelope where value > 1e-3 { floorValues.append(value) }
        let scale = floorValues.isEmpty ? 1 : Self.percentile(floorValues, 0.95)
        var index = 0
        while index < frameCount {
            envelope[index] = Swift.min(1, envelope[index] / Swift.max(scale, 1e-9))
            index &+= 1
        }

        var down = [Double](repeating: 0, count: frameCount)
        let chords = track.chords
        let weights = [self.bassWeight, self.massWeight, self.durationWeight, self.chromaWeight, self.wideChromaWeight, self.pedalWeight, self.gapWeight]
        var chordOnsets: [Double] = []
        chordOnsets.reserveCapacity(chords.count)
        for chord in chords { chordOnsets.append(chord.leadingOnset) }
        let normalized = Self.standardized(chordOnsets.map { cues.cues(at: $0, unit: 1, halfWidth: 0.08) })
        index = 0
        while index < chordOnsets.count {
            var value = 0.0
            var cue = 0
            while cue < 7 {
                value += normalized[index][cue] * weights[cue]
                cue &+= 1
            }
            value = Swift.max(0, value)
            let frame = Int((chordOnsets[index] / hop).rounded())
            var offset = -1
            while offset <= 1 {
                let target = frame &+ offset
                if target >= 0 && target < frameCount {
                    down[target] = Swift.max(down[target], value * (offset == 0 ? 1 : 0.6))
                }
                offset &+= 1
            }
            index &+= 1
        }

        let beatLikelihood = envelope.map { log($0 + self.beatFloor) }
        let offBeatLikelihood = envelope.map { log(Swift.max(1e-6, 1 - self.offBeatWeight * $0) + self.beatFloor) }

        // MARK: State space

        var periods: [Int] = []
        var step = 0
        while step < Self.beatLengthCount {
            let period = Int((Self.minimumBeat / hop * pow(Self.maximumBeat / Self.minimumBeat, Double(step) / Double(Self.beatLengthCount &- 1))).rounded())
            if periods.last != period { periods.append(period) }
            step &+= 1
        }
        let periodCount = periods.count
        let meters = Self.meters
        let bonuses = meters.map { $0 == 3 ? self.tripleMeterBonus : ($0 == 4 ? self.quadrupleMeterBonus : 0) }
        let regions = periods.map { Swift.max(1, Int((Double($0) / self.beatRegionDivisor).rounded())) }

        // A block holds the positions of one (meter, period) pair; blocks are ordered by meter, then period.
        var blockStarts: [Int] = []
        var blockLengths: [Int] = []
        var beatStartOffsets: [Int] = [] // where the backpointers of a block's beat starts begin, per frame
        var stateCount = 0
        var beatStartCount = 0
        for meter in meters {
            for period in periods {
                blockStarts.append(stateCount)
                blockLengths.append(meter &* period)
                beatStartOffsets.append(beatStartCount)
                stateCount &+= meter &* period
                beatStartCount &+= meter
            }
        }
        let blockCount = blockStarts.count

        // Frames where an anchor forces a bar to start.
        var forced = [Bool](repeating: false, count: frameCount)
        var anchorOfFrame: [Int: Double] = [:]
        var lastForced = Int.min / 2
        let minimumGap = 2 &* periods[0]
        for anchor in anchors {
            let frame = Int((anchor / hop).rounded())
            guard frame >= 0 && frame < frameCount && frame &- lastForced >= minimumGap else { continue }
            forced[frame] = true
            anchorOfFrame[frame] = anchor
            lastForced = frame
        }

        // MARK: Viterbi

        var score = [Double](repeating: 0, count: stateCount)
        var next = [Double](repeating: 0, count: stateCount)
        var back = [Int32](repeating: -1, count: frameCount &* beatStartCount)

        var block = 0
        while block < blockCount {
            let meterIndex = block / periodCount
            let period = periods[block % periodCount]
            let region = regions[block % periodCount]
            var position = 0
            while position < blockLengths[block] {
                var value: Double
                if position % period < region {
                    value = beatLikelihood[0]
                    if position < region { value += self.downbeatGain * down[0] - self.downbeatCost + bonuses[meterIndex] }
                } else {
                    value = offBeatLikelihood[0]
                }
                score[blockStarts[block] &+ position] = value
                position &+= 1
            }
            block &+= 1
        }
        if forced[0] { Self.forceBarStarts(&score, blockStarts: blockStarts, blockLengths: blockLengths) }

        score.withUnsafeMutableBufferPointer { current in
            next.withUnsafeMutableBufferPointer { following in
                back.withUnsafeMutableBufferPointer { back in
                    let current = current.baseAddress!
                    let following = following.baseAddress!
                    var frame = 1
                    while frame < frameCount {
                        var offBeat = offBeatLikelihood[frame]
                        let beatExtra = beatLikelihood[frame] - offBeatLikelihood[frame]
                        let downExtra = self.downbeatGain * down[frame] - self.downbeatCost

                        // The pointer moves on by one frame: shift every block and add the emission between beats, then correct the frames near the start of each beat.
                        var block = 0
                        while block < blockCount {
                            let start = blockStarts[block]
                            vDSP_vsaddD(current + start, 1, &offBeat, following + (start &+ 1), 1, vDSP_Length(blockLengths[block] &- 1))
                            let meterIndex = block / periodCount
                            let period = periods[block % periodCount]
                            let region = regions[block % periodCount]
                            let meter = meters[meterIndex]
                            var beat = 0
                            while beat < meter {
                                var offset = 1
                                while offset < Swift.max(1, region) && offset < period {
                                    following[start &+ beat &* period &+ offset] += beatExtra + (beat == 0 ? downExtra + bonuses[meterIndex] : 0)
                                    offset &+= 1
                                }
                                beat &+= 1
                            }
                            block &+= 1
                        }

                        // A beat starts after the previous beat of any nearby beat length, and a bar also after a bar of another meter.
                        block = 0
                        while block < blockCount {
                            let meterIndex = block / periodCount
                            let periodIndex = block % periodCount
                            let period = periods[periodIndex]
                            let meter = meters[meterIndex]
                            var beat = 0
                            while beat < meter {
                                var best = -Double.infinity
                                var argument: Int32 = -1
                                let previousBeat = (beat &- 1 &+ meter) % meter
                                var other = Swift.max(0, periodIndex &- Self.maximumBeatLengthStep)
                                let last = Swift.min(periodCount &- 1, periodIndex &+ Self.maximumBeatLengthStep)
                                while other <= last {
                                    let source = blockStarts[meterIndex &* periodCount &+ other] &+ (previousBeat &+ 1) &* periods[other] &- 1
                                    let value = current[source] - self.tempoChangeCost * abs(log(Double(periods[other]) / Double(period)))
                                    if value > best { best = value; argument = Int32(source) }
                                    other &+= 1
                                }
                                if beat == 0 {
                                    var otherMeter = 0
                                    while otherMeter < meters.count {
                                        if otherMeter != meterIndex {
                                            let source = blockStarts[otherMeter &* periodCount &+ periodIndex] &+ meters[otherMeter] &* period &- 1
                                            let value = current[source] - self.meterChangeCost
                                            if value > best { best = value; argument = Int32(source) }
                                        }
                                        otherMeter &+= 1
                                    }
                                }
                                following[blockStarts[block] &+ beat &* period] = best + beatLikelihood[frame] + (beat == 0 ? downExtra + bonuses[meterIndex] : 0)
                                back[frame &* beatStartCount &+ beatStartOffsets[block] &+ beat] = argument
                                beat &+= 1
                            }
                            block &+= 1
                        }

                        if forced[frame] {
                            var block = 0
                            while block < blockCount {
                                var position = 1
                                while position < blockLengths[block] {
                                    following[blockStarts[block] &+ position] = -.infinity
                                    position &+= 1
                                }
                                block &+= 1
                            }
                        }

                        // Keep the numbers small.
                        var maximum = 0.0
                        vDSP_maxvD(following, 1, &maximum, vDSP_Length(stateCount))
                        var negated = -maximum
                        vDSP_vsaddD(following, 1, &negated, current, 1, vDSP_Length(stateCount))
                        frame &+= 1
                    }
                }
            }
        }

        // MARK: Backtrack

        var state = 0
        index = 1
        while index < stateCount {
            if score[index] > score[state] { state = index }
            index &+= 1
        }
        var blockOfState = [Int](repeating: 0, count: stateCount)
        block = 0
        while block < blockCount {
            var position = 0
            while position < blockLengths[block] {
                blockOfState[blockStarts[block] &+ position] = block
                position &+= 1
            }
            block &+= 1
        }
        var barFrames: [Int] = []
        var frame = frameCount &- 1
        while frame >= 0 {
            let block = blockOfState[state]
            let position = state &- blockStarts[block]
            if position == 0 { barFrames.append(frame) }
            if frame == 0 { break }
            let period = periods[block % periodCount]
            if position % period != 0 {
                state &-= 1
            } else {
                state = Int(back[frame &* beatStartCount &+ beatStartOffsets[block] &+ position / period])
            }
            frame &-= 1
        }

        // MARK: Times

        let onsets = notes.map(\.onset)
        let first = onsets[0]
        var result: [Double] = []
        result.reserveCapacity(barFrames.count &+ anchors.count)
        var position = barFrames.count &- 1
        while position >= 0 {
            let frame = barFrames[position]
            if let anchor = anchorOfFrame[frame] {
                result.append(anchor)
            } else {
                let time = Self.snapped(Double(frame) * hop, to: onsets, within: 1.5 * hop)
                if time >= first - 0.1 { result.append(time) }
            }
            position &-= 1
        }
        result.append(contentsOf: anchors)
        result.sort()
        var unique: [Double] = []
        unique.reserveCapacity(result.count)
        for time in result where unique.last.map({ time > $0 }) ?? true { unique.append(time) }
        return unique
    }


    // MARK: - Helpers

    /// The finite, non-negative anchors, sorted, without duplicates.
    static func sanitized(_ prior: [Double]) -> [Double] {
        let sorted = prior.filter { $0.isFinite && $0 >= 0 }.sorted()
        var result: [Double] = []
        result.reserveCapacity(sorted.count)
        for anchor in sorted where result.last.map({ anchor - $0 > 1e-9 }) ?? true { result.append(anchor) }
        return result
    }

    /// Leaves only the bar starts reachable: every other position of every block becomes impossible.
    private static func forceBarStarts(_ score: inout [Double], blockStarts: [Int], blockLengths: [Int]) {
        var block = 0
        while block < blockStarts.count {
            var position = 1
            while position < blockLengths[block] {
                score[blockStarts[block] &+ position] = -.infinity
                position &+= 1
            }
            block &+= 1
        }
    }

    /// The value at the rounded rank `q * (count - 1)` of `values`.
    static func percentile(_ values: [Double], _ q: Double) -> Double {
        let sorted = values.sorted()
        let rank = Swift.min(sorted.count &- 1, Swift.max(0, Int((Double(sorted.count &- 1) * q).rounded())))
        return sorted[rank]
    }

    /// Each column minus its mean, divided by its standard deviation; a constant column becomes `0`.
    static func standardized(_ rows: [[Double]]) -> [[Double]] {
        guard let width = rows.first?.count else { return rows }
        var result = rows
        var column = 0
        while column < width {
            var sum = 0.0
            for row in rows { sum += row[column] }
            let mean = sum / Double(rows.count)
            var squares = 0.0
            for row in rows { squares += (row[column] - mean) * (row[column] - mean) }
            let deviation = (squares / Double(Swift.max(1, rows.count))).squareRoot()
            var index = 0
            while index < rows.count {
                result[index][column] = deviation > 1e-9 ? (rows[index][column] - mean) / deviation : 0
                index &+= 1
            }
            column &+= 1
        }
        return result
    }

    /// `time`, moved to the nearest onset closer than `tolerance`, if there is one.
    static func snapped(_ time: Double, to onsets: [Double], within tolerance: Double) -> Double {
        var low = 0
        var high = onsets.count
        while low < high {
            let middle = (low &+ high) / 2
            if onsets[middle] < time { low = middle &+ 1 } else { high = middle }
        }
        var best = time
        var distance = tolerance
        for candidate in [low &- 1, low] where candidate >= 0 && candidate < onsets.count && abs(onsets[candidate] - time) < distance {
            distance = abs(onsets[candidate] - time)
            best = onsets[candidate]
        }
        return best
    }

}
