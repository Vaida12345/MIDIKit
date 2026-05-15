//
//  LocalBarRegionsTests.swift
//  MIDIKit
//
//  Created by Codex on 2026-04-06.
//

@testable
import MIDIKit
import Testing


@Suite("Local Bar Regions")
struct LocalBarRegionsTests {

    @Test
    func stableBarLengthProducesSingleRegion() {
        let indexed = Self.makeIndexed(
            notes: Self.metricPattern(start: 0, bars: 10, barLength: 4)
        )

        let regions = indexed.localBarRegions(windowDuration: 6, overlapRatio: 0.5, barTolerance: 0.12)

        #expect(!regions.isEmpty)
        #expect(regions.count <= 2)
        #expect(abs(regions[0].barLength - 4.0) < 0.45)
    }

    @Test
    func transitionFromFourToThreeIsSegmented() {
        var notes = Self.metricPattern(start: 0, bars: 5, barLength: 4)
        notes += Self.metricPattern(start: 20, bars: 6, barLength: 3)

        // Strong boundary emphasis around the structural change.
        notes.append(MIDINote(onset: 19.9, offset: 20.9, note: 36, velocity: 122))
        notes.append(MIDINote(onset: 20.0, offset: 21.6, note: 48, velocity: 116))

        let indexed = Self.makeIndexed(notes: notes)
        let regions = indexed.localBarRegions(windowDuration: 6, overlapRatio: 0.5, barTolerance: 0.16)

        #expect(regions.count >= 2)
        #expect(regions.contains(where: { abs($0.barLength - 4.0) < 1.0 }))

        let hasClearDrop = (1..<regions.count).contains { index in
            regions[index].barLength < regions[index - 1].barLength - 0.5
        }
        #expect(hasClearDrop)

        for i in 1..<regions.count {
            #expect(regions[i].onset >= regions[i - 1].onset)
        }
    }

}


private extension LocalBarRegionsTests {

    static func makeIndexed(notes: [MIDINote], sustains: [MIDISustainEvent] = []) -> IndexedContainer {
        let track = MIDITrack(notes: notes, sustains: sustains)
        let container = MIDIContainer(tracks: [track])
        return container.indexed()
    }

    static func metricPattern(start: Double, bars: Int, barLength: Double) -> [MIDINote] {
        var notes: [MIDINote] = []
        let beats = bars * Int(barLength)

        for beatIndex in 0..<beats {
            let onset = start + Double(beatIndex)
            let isBarStart = beatIndex % Int(barLength) == 0

            if isBarStart {
                notes.append(MIDINote(onset: onset, offset: onset + 0.95, note: 36, velocity: 118))
                notes.append(MIDINote(onset: onset + 0.02, offset: onset + 0.74, note: 52, velocity: 96))
                notes.append(MIDINote(onset: onset + 0.04, offset: onset + 0.58, note: 64, velocity: 88))
            } else {
                notes.append(MIDINote(onset: onset + 0.03, offset: onset + 0.34, note: 72, velocity: 54))
                if beatIndex % 2 == 0 {
                    notes.append(MIDINote(onset: onset + 0.5, offset: onset + 0.72, note: 79, velocity: 42))
                }
            }
        }

        return notes
    }

}
