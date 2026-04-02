//
//  DownbeatsTests.swift
//  MIDIKit
//
//  Created by Codex on 2026-04-02.
//

@testable
import MIDIKit
import Testing


@Suite("Downbeats")
struct DownbeatsTests {

    @Test
    func anchorPrefixAndZero() {
        let indexed = Self.makeIndexed(
            notes: Self.metricPattern(start: 0, bars: 6, barLength: 4)
        )

        let downbeats = indexed.downbeats(prior: [4.0, 8.0])

        #expect(downbeats.count >= 3)
        #expect(downbeats[0] == 0.0)
        #expect(downbeats[1] == 4.0)
        #expect(downbeats[2] == 8.0)
    }

    @Test
    func strictlyIncreasing() {
        let notes = Self.metricPattern(start: 0, bars: 4, barLength: 4)
            + Self.metricPattern(start: 16, bars: 4, barLength: 3)
        let indexed = Self.makeIndexed(notes: notes)

        let downbeats = indexed.downbeats()

        #expect(!downbeats.isEmpty)
        for i in 1..<downbeats.count {
            #expect(downbeats[i] > downbeats[i - 1])
        }
    }

    @Test
    func extendsAfterPriorWithStableSpacing() {
        let indexed = Self.makeIndexed(
            notes: Self.metricPattern(start: 0, bars: 8, barLength: 4)
        )

        let downbeats = indexed.downbeats(prior: [4.0, 8.0, 12.0])

        #expect(downbeats.count >= 5)
        #expect(downbeats[0] == 0.0)
        #expect(downbeats[1] == 4.0)
        #expect(downbeats[2] == 8.0)
        #expect(downbeats[3] == 12.0)

        let firstInferred = downbeats[4] - downbeats[3]
        #expect(abs(firstInferred - 4.0) < 0.75)
    }

    @Test
    func barLengthCanChangeAtStrongBoundary() {
        var notes = Self.metricPattern(start: 0, bars: 4, barLength: 4)
        notes += Self.metricPattern(start: 16, bars: 4, barLength: 3)

        // Add a strong sectional boundary around the switch.
        notes.append(MIDINote(onset: 15.9, offset: 16.8, note: 36, velocity: 122))
        notes.append(MIDINote(onset: 16.0, offset: 17.4, note: 48, velocity: 118))

        let indexed = Self.makeIndexed(notes: notes)
        let downbeats = indexed.downbeats()
        let gaps = downbeats.gaps()

        #expect(gaps.contains(where: { abs($0 - 4.0) < 0.7 }))
        #expect(gaps.contains(where: { abs($0 - 3.0) < 0.7 }))
    }

}


private extension DownbeatsTests {

    static func makeIndexed(notes: [MIDINote], sustains: [MIDISustainEvent] = []) -> IndexedContainer {
        let track = MIDITrack(notes: notes, sustains: sustains)
        let container = MIDIContainer(tracks: [track])
        return container.indexed()
    }

    static func metricPattern(start: Double, bars: Int, barLength: Double) -> [MIDINote] {
        var notes: [MIDINote] = []
        notes.reserveCapacity(bars * 6)

        let beats = bars * Int(barLength)
        for beatIndex in 0..<beats {
            let onset = start + Double(beatIndex)
            let isBarStart = beatIndex % Int(barLength) == 0

            if isBarStart {
                notes.append(MIDINote(onset: onset, offset: onset + 0.95, note: 40, velocity: 112))
                notes.append(MIDINote(onset: onset, offset: onset + 0.75, note: 52, velocity: 96))
                notes.append(MIDINote(onset: onset + 0.03, offset: onset + 0.7, note: 64, velocity: 88))
            } else {
                notes.append(MIDINote(onset: onset + 0.02, offset: onset + 0.32, note: 70, velocity: 48))
            }
        }

        return notes
    }

}
