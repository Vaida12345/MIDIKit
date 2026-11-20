//
//  IndexedTrackDownbeatsTests.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import Testing
import Foundation
import MIDIKit
@testable
import IndexedTrack


// MARK: - Support

/// A piano figure with known bar lines: bass, a chord and the pedal on each downbeat, a lighter note on every other beat, and a harmony that changes every bar.
private struct BarFigure {

    var notes: [MIDINote] = []
    var sustains: [MIDISustainEvent] = []
    /// The true downbeats, in beats.
    var downbeats: [Double] = []

    /// Root, third and fifth of the harmony of each bar, cycling: C, G, A minor, F.
    private static let harmonies: [[UInt8]] = [[48, 64, 67], [43, 62, 67], [45, 64, 69], [41, 65, 69]]

    /// - Parameters:
    ///   - meter: Beats per bar.
    ///   - bars: The number of bars.
    ///   - pickup: Beats of a pickup before the first bar, each a single light note.
    ///   - beatLength: The length of the beat, in beats, as a function of the bar index, so that the tempo can drift.
    ///   - accompaniment: Whether the other beats carry a two-note chord, as in a waltz, instead of a single note.
    init(meter: Int, bars: Int, pickup: Int = 0, start: Double = 1, accompaniment: Bool = false, beatLength: (Int) -> Double = { _ in 1 }) {
        var time = start
        var beat = 0
        while beat < pickup {
            let length = beatLength(0)
            notes.append(note(time, time + length * 0.5, 72, velocity: 55))
            time += length
            beat += 1
        }
        var bar = 0
        while bar < bars {
            let length = beatLength(bar)
            let harmony = Self.harmonies[bar % Self.harmonies.count]
            downbeats.append(time)
            notes.append(note(time, time + length * Double(meter) - gap, harmony[0], velocity: 100))
            notes.append(note(time, time + length * 0.9, harmony[1] + 12, velocity: 80))
            notes.append(note(time, time + length * 0.9, harmony[2] + 12, velocity: 80))
            sustains.append(MIDISustainEvent(onset: time + 0.05, offset: time + length * Double(meter) - 0.05))
            var other = 1
            while other < meter {
                let onset = time + length * Double(other)
                if accompaniment {
                    notes.append(note(onset, onset + length * 0.5, harmony[1] + 12, velocity: 60))
                    notes.append(note(onset, onset + length * 0.5, harmony[2] + 12, velocity: 60))
                } else {
                    notes.append(note(onset, onset + length * 0.5, harmony[1 + other % 2] + 12, velocity: 55))
                }
                other += 1
            }
            time += length * Double(meter)
            bar += 1
        }
    }

    func makeTrack(profile: some AnalysisProfile = .generic) -> IndexedTrack {
        IndexedTrack(MIDIContainer(tracks: [MIDITrack(notes: notes, sustains: sustains)]), profile: profile)
    }

}

/// Downbeat F-measure with a ±0.14 beat (±70 ms) window, one-to-one.
private func fMeasure(_ estimate: [Double], _ reference: [Double]) -> Double {
    guard !estimate.isEmpty && !reference.isEmpty else { return estimate.isEmpty && reference.isEmpty ? 1 : 0 }
    var i = 0, j = 0, hits = 0
    while i < reference.count && j < estimate.count {
        let difference = estimate[j] - reference[i]
        if abs(difference) <= 0.14 { hits += 1; i += 1; j += 1 } else if difference < 0 { j += 1 } else { i += 1 }
    }
    let precision = Double(hits) / Double(estimate.count), recall = Double(hits) / Double(reference.count)
    return precision + recall > 0 ? 2 * precision * recall / (precision + recall) : 0
}

private func isStrictlyIncreasing(_ values: [Double]) -> Bool {
    zip(values, values.dropFirst()).allSatisfy { $0 < $1 }
}

private func medianBar(_ downbeats: [Double]) -> Double {
    let gaps = zip(downbeats, downbeats.dropFirst()).map { $1 - $0 }.sorted()
    return gaps.isEmpty ? .nan : gaps[gaps.count / 2]
}

/// A profile whose downbeats are fixed.
private struct FixedDownbeats: AnalysisProfile {
    let values: [Double]
    func formChords(in track: IndexedTrack) -> IndexedTrack.Chords { ChordArbiter.generic.formChords(in: track) }
    func downbeats(in track: IndexedTrack, prior: [Double]) -> [Double] { values }
}

/// A profile that implements only the required hooks.
private struct ChordsOnly: AnalysisProfile {
    func formChords(in track: IndexedTrack) -> IndexedTrack.Chords { ChordArbiter.generic.formChords(in: track) }
}


// MARK: - Tests

@Suite(.timeLimit(.minutes(1)))
struct IndexedTrackDownbeatsTests {

    @Test func emptyTrackReturnsTheSanitizedPrior() {
        let empty = track([])
        #expect(empty.downbeats() == [])
        #expect(empty.downbeats(prior: [4, .nan, -1, 2, 2]) == [2, 4])
    }

    @Test func singleNoteDoesNotCrash() {
        let result = track([note(1, 2, 60)]).downbeats()
        #expect(isStrictlyIncreasing(result))
        #expect(result.count <= 1)
    }

    @Test func findsTheBarsOfFourFour() {
        let figure = BarFigure(meter: 4, bars: 16)
        let result = figure.makeTrack().downbeats()
        #expect(isStrictlyIncreasing(result))
        #expect(fMeasure(result, figure.downbeats) >= 0.9, "\(result)")
    }

    /// The tuned constants find this waltz in bars of six beats, every other bar line: a doubled bar, the most common metric-level error on real performances too. What must hold is that every bar line found is a true one.
    @Test func findsTheBarLinesOfAWaltz() {
        let figure = BarFigure(meter: 3, bars: 20, accompaniment: true)
        let result = figure.makeTrack().downbeats()
        let truth = Set(figure.downbeats)
        #expect(result.count >= 8, "\(result)")
        #expect(result.allSatisfy { found in truth.contains { abs($0 - found) <= 0.14 } }, "\(result)")
        let multiple = medianBar(result) / 3
        #expect(abs(multiple - multiple.rounded()) <= 0.05 && multiple.rounded() >= 1, "\(result)")
    }

    @Test func followsARitardando() {
        let bars = 16
        let figure = BarFigure(meter: 4, bars: bars) { 1 + 0.5 * Double($0) / Double(bars - 1) }
        let result = figure.makeTrack().downbeats()
        #expect(fMeasure(result, figure.downbeats) >= 0.85, "\(result)")
    }

    @Test func skipsAPickup() throws {
        let figure = BarFigure(meter: 4, bars: 12, pickup: 2)
        let result = figure.makeTrack().downbeats()
        let first = try #require(result.first)
        #expect(abs(first - figure.downbeats[0]) <= 0.14, "\(result)")
        #expect(fMeasure(result, figure.downbeats) >= 0.9, "\(result)")
    }

    @Test func pianoTranscriptionNeverReadsOffsets() {
        let figure = BarFigure(meter: 4, bars: 12)
        var stretched = figure
        // Same onsets, every note at least 0.2 beat long, so the glissando test and the chords stay the same.
        stretched.notes = figure.notes.map { var note = $0; note.offset = note.onset + Swift.max(0.2, (note.offset - note.onset) * 3); return note }
        let original = figure.makeTrack(), changed = stretched.makeTrack()
        #expect(original.chords.map(\.leadingOnset) == changed.chords.map(\.leadingOnset))
        #expect(original.notes.map(\.offset) != changed.notes.map(\.offset))
        #expect(DownbeatTracker.pianoTranscription.downbeats(in: original) == DownbeatTracker.pianoTranscription.downbeats(in: changed))
    }

    @Test func durationCueFollowsReadsOffsets() {
        let track = BarFigure(meter: 4, bars: 4).makeTrack()
        let downbeat = track.notes[0].onset
        let reading = DownbeatCues(track: track, readsOffsets: true).cues(at: downbeat, unit: 1, halfWidth: 0.08)
        let ignoring = DownbeatCues(track: track, readsOffsets: false).cues(at: downbeat, unit: 1, halfWidth: 0.08)
        #expect(reading[2] > 0)
        #expect(ignoring[2] == 0)
        #expect(DownbeatCues(track: track, readsOffsets: false).soundingOffsets == track.notes.map { $0.onset + 0.5 })
    }

    @Test func priorAnchorsAreKeptExactly() {
        let figure = BarFigure(meter: 4, bars: 16)
        let track = figure.makeTrack()
        #expect(track.downbeats(prior: []) == track.downbeats())

        let offBeat = figure.downbeats[5] + 1.01
        let result = track.downbeats(prior: [offBeat, figure.downbeats[10]])
        #expect(isStrictlyIncreasing(result))
        #expect(result.contains(offBeat))
        #expect(result.contains(figure.downbeats[10]))

        let messy = track.downbeats(prior: [figure.downbeats[8], .nan, -3, figure.downbeats[2], figure.downbeats[2], figure.downbeats[2] + 1e-10, .infinity])
        #expect(isStrictlyIncreasing(messy))
        #expect(messy.contains(figure.downbeats[2]))
        #expect(messy.contains(figure.downbeats[8]))
        #expect(!messy.contains(figure.downbeats[2] + 1e-10))
    }

    /// An anchor far past the end, or a divisor that gives no region, neither traps nor breaks the decoding.
    @Test func extremeInputsDoNotTrap() {
        let track = BarFigure(meter: 4, bars: 4).makeTrack()
        let result = track.downbeats(prior: [1e20])
        #expect(result.contains(1e20))
        #expect(isStrictlyIncreasing(result))

        // A silence of several beats, which a floor of 0 or less made impossible on every path.
        let sparse = IndexedTrack(MIDIContainer(tracks: [MIDITrack(notes: [MIDINote(onset: 0, offset: 0.5, pitch: 60, velocity: 80), MIDINote(onset: 10, offset: 10.5, pitch: 62, velocity: 80)])]))
        for floor in [0, -0.01, .nan, .infinity] as [Double] {
            var tracker = DownbeatTracker.generic
            tracker.beatFloor = floor
            #expect(isStrictlyIncreasing(tracker.downbeats(in: sparse)), "\(floor)")
        }

        for divisor in [0, -1, .nan, .infinity] as [Double] {
            var tracker = DownbeatTracker.generic
            tracker.beatRegionDivisor = divisor
            #expect(isStrictlyIncreasing(tracker.downbeats(in: track)))
        }
    }

    @Test func anchorsCloseTogetherAreKeptButDoNotBreakDecoding() {
        let figure = BarFigure(meter: 4, bars: 8)
        let anchors = [figure.downbeats[3], figure.downbeats[3] + 0.3, figure.downbeats[3] + 0.6]
        let result = figure.makeTrack().downbeats(prior: anchors)
        #expect(isStrictlyIncreasing(result))
        #expect(anchors.allSatisfy { result.contains($0) })
        #expect(result.allSatisfy { $0.isFinite })
    }

    @Test func profileDecides() {
        let figure = BarFigure(meter: 4, bars: 8)
        #expect(figure.makeTrack().downbeats() == DownbeatTracker.generic.downbeats(in: figure.makeTrack()))
        #expect(figure.makeTrack(profile: FixedDownbeats(values: [1, 2, 3])).downbeats() == [1, 2, 3])
        #expect(figure.makeTrack(profile: ChordsOnly()).downbeats() == DownbeatTracker.generic.downbeats(in: figure.makeTrack(profile: ChordsOnly())))
        #expect(figure.makeTrack(profile: ChordsOnly()).downbeats(prior: [7]) == DownbeatTracker.generic.downbeats(in: figure.makeTrack(profile: ChordsOnly()), prior: [7]))
        #expect(figure.makeTrack(profile: .transkun).downbeats() == DownbeatTracker.transkun.downbeats(in: figure.makeTrack(profile: .transkun)))
        #expect(figure.makeTrack(profile: .pianoTranscription).downbeats(prior: [7]) == DownbeatTracker.pianoTranscription.downbeats(in: figure.makeTrack(profile: .pianoTranscription), prior: [7]))
    }

    @Test func isDeterministic() {
        var rng = IndexedTrackRNG(seed: 7)
        let notes = cleanInput(seed: rng.next(), count: 300)
        let first = track(notes).downbeats(), second = track(notes).downbeats()
        #expect(first == second)
        #expect(isStrictlyIncreasing(first))
    }

    @Test func presetsArePinned() {
        let generic = DownbeatTracker.generic
        #expect([generic.bassWeight, generic.massWeight, generic.durationWeight, generic.chromaWeight, generic.wideChromaWeight, generic.pedalWeight, generic.gapWeight] == [1.6, 0.3, 1.1, 1, 0.6, 0.5, 0.3])
        #expect([generic.tempoChangeCost, generic.beatFloor, generic.offBeatWeight, generic.downbeatGain, generic.downbeatCost, generic.meterChangeCost, generic.beatRegionDivisor, generic.tripleMeterBonus, generic.quadrupleMeterBonus] == [30, 0.028, 0.6, 1.6, 0.7, 8, 20, 0.4, 0.8])
        #expect(generic.readsOffsets)

        let transkun = DownbeatTracker.transkun
        #expect([transkun.bassWeight, transkun.massWeight, transkun.durationWeight, transkun.chromaWeight, transkun.wideChromaWeight, transkun.pedalWeight, transkun.gapWeight] == [1.2, 0.1, 1.5, 0.6, 1, 0.7, 0.3])
        #expect([transkun.tempoChangeCost, transkun.beatFloor, transkun.offBeatWeight, transkun.downbeatGain, transkun.downbeatCost, transkun.meterChangeCost, transkun.beatRegionDivisor, transkun.tripleMeterBonus, transkun.quadrupleMeterBonus] == [30, 0.02, 0.6, 1.6, 0.7, 8, 20, 0.4, 0.6])
        #expect(transkun.readsOffsets)

        let pianoTranscription = DownbeatTracker.pianoTranscription
        #expect([pianoTranscription.bassWeight, pianoTranscription.massWeight, pianoTranscription.durationWeight, pianoTranscription.chromaWeight, pianoTranscription.wideChromaWeight, pianoTranscription.pedalWeight, pianoTranscription.gapWeight] == [1.4, 0.3, 0.7, 0.6, 0.6, 0.3, 0.3])
        #expect([pianoTranscription.tempoChangeCost, pianoTranscription.beatFloor, pianoTranscription.offBeatWeight, pianoTranscription.downbeatGain, pianoTranscription.downbeatCost, pianoTranscription.meterChangeCost, pianoTranscription.beatRegionDivisor, pianoTranscription.tripleMeterBonus, pianoTranscription.quadrupleMeterBonus] == [30, 0.028, 0.6, 1.6, 0.7, 11.2, 14, 0.2, 0.4])
        #expect(!pianoTranscription.readsOffsets)
    }

}
