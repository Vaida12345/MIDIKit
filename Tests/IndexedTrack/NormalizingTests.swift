//
//  NormalizingTests.swift
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

/// Random sustains around `0...end`: some overlap, some touch, some are closer than the margin, and there may be none.
private func randomSustains(seed: UInt64, end: Double) -> [MIDISustainEvent] {
    var rng = IndexedTrackRNG(seed: seed &+ 7_000)
    let count = rng.int(0...20)
    return (0..<count).map { _ in
        let onset = Double(rng.int(0...Int(end * 16))) / 16
        let duration = Double(rng.int(1...48)) / 16
        return MIDISustainEvent(onset: onset, offset: onset + duration)
    }
}

/// Runs the old `IndexedContainer.normalize` on the notes and sustains of `track`, and returns its notes in the order of `track.notes`.
private func oldNormalized(_ track: IndexedTrack, preserve: IndexedTrack.PreserveSettings) -> [MIDINote] {
    let old = IndexedContainer(container: track.makeContainer())
    defer { withExtendedLifetime(old) {} }
    #expect(ChordFigures.orderedNotes(of: old).map(\.pointee) == track.notes, "The old container must hold the same notes in the same order.")

    old.normalize(preserve: IndexedContainer.PreserveSettings(rawValue: preserve.rawValue)!, optimizeFor: nil)
    return ChordFigures.orderedNotes(of: old).map(\.pointee)
}

/// The onset of the next note on the same key as each note, or `nil` for the last.
private func nextOnsetsOnKey(_ track: IndexedTrack) -> [Double?] {
    var result = [Double?](repeating: nil, count: track.notes.count)
    let lanes = track.lanes
    for pitch in 21...108 as ClosedRange<UInt8> {
        let lane = lanes[lane: pitch]
        for position in lane.indices.dropLast() {
            result[lane.noteIndex(at: position)] = lane[position + 1].onset
        }
    }
    return result
}

/// A note at 60 from 0 to `offset`, followed by a separate chord at 72 at `next`.
private func pair(offset: Double, next: Double, sustains: [MIDISustainEvent]) -> IndexedTrack {
    track([note(0, offset, 60), note(next, next + 0.1, 72)], sustains: sustains)
}

private func normalizedOffset(_ track: IndexedTrack, _ preserve: IndexedTrack.PreserveSettings) -> Double {
    track.normalizing(preserve: preserve).notes[0].offset
}


// MARK: - Tests

@Suite(.timeLimit(.minutes(1)))
struct NormalizingTests {

    /// The same as the old `normalize`, except where it let a note end exactly where the next note on its key starts.
    @Test(arguments: 0..<30)
    func matchesTheOldNormalize(seed: Int) {
        let notes = cleanInput(seed: UInt64(seed) &+ 500, count: 200)
        let end = notes.map(\.offset).max() ?? 0
        let indexed = track(notes, sustains: randomSustains(seed: UInt64(seed), end: end))
        let nextOnsets = nextOnsetsOnKey(indexed)

        for preserve in IndexedTrack.PreserveSettings.allCases {
            let new = indexed.normalizing(preserve: preserve).notes
            let old = oldNormalized(indexed, preserve: preserve)
            #expect(new.map(\.onset) == old.map(\.onset))

            for index in new.indices where new[index].offset != old[index].offset {
                let next = nextOnsets[index]
                #expect(next != nil && old[index].offset == next! && new[index].offset == next!.nextDown, "\(preserve), note \(index): old \(old[index].offset), new \(new[index].offset), next \(String(describing: next))")
            }
        }
    }

    @Test
    func withinOneSustain() {
        let indexed = pair(offset: 3, next: 2, sustains: [MIDISustainEvent(onset: 0, offset: 5)])
        #expect(normalizedOffset(indexed, .acousticResult) == 2)
        #expect(normalizedOffset(indexed, .notesDisplay) == 2)
    }

    @Test
    func adjacentSustains() {
        let sustains = [MIDISustainEvent(onset: 0, offset: 0.5), MIDISustainEvent(onset: 1.5, offset: 4)]
        // The next sustain starts before the next chord: the note keeps reaching it.
        #expect(normalizedOffset(pair(offset: 3, next: 2, sustains: sustains), .acousticResult) == 3)
        // The next chord starts first.
        let indexed = pair(offset: 3, next: 1, sustains: sustains)
        #expect(normalizedOffset(indexed, .acousticResult) == 1.5 + 0.1)
        #expect(normalizedOffset(indexed, .notesDisplay) == 1)
    }

    @Test
    func spansThreeSustains() {
        let indexed = pair(offset: 3, next: 0.8, sustains: [MIDISustainEvent(onset: 0, offset: 0.5), MIDISustainEvent(onset: 1, offset: 1.2), MIDISustainEvent(onset: 2, offset: 4)])
        #expect(normalizedOffset(indexed, .acousticResult) == 3)
        #expect(normalizedOffset(indexed, .notesDisplay) == 0.8)
    }

    @Test
    func sustainAtTheOffsetOnly() {
        let indexed = pair(offset: 3, next: 0.8, sustains: [MIDISustainEvent(onset: 1, offset: 4)])
        #expect(normalizedOffset(indexed, .acousticResult) == 1 + 0.1)
        #expect(normalizedOffset(indexed, .notesDisplay) == 0.8)
    }

    @Test
    func sustainAtTheOnsetOnly() {
        let indexed = pair(offset: 3, next: 1.2, sustains: [MIDISustainEvent(onset: 0, offset: 1), MIDISustainEvent(onset: 1.5, offset: 2)])
        #expect(normalizedOffset(indexed, .acousticResult) == 1.5 + 0.1)
        #expect(normalizedOffset(indexed, .notesDisplay) == 1.2)
    }

    /// A release within 1/4 beat after the sustain counts as within it.
    @Test
    func releaseWithinTheMargin() {
        let indexed = pair(offset: 3, next: 2.5, sustains: [MIDISustainEvent(onset: 0, offset: 2.9)])
        #expect(normalizedOffset(indexed, .acousticResult) == 2.5)
    }

    /// A release in a gap shorter than 1/2 beat between two sustains counts as within the first.
    @Test
    func releaseInATinyGap() {
        let indexed = pair(offset: 2.28, next: 2.1, sustains: [MIDISustainEvent(onset: 0, offset: 2), MIDISustainEvent(onset: 2.3, offset: 2.6)])
        #expect(normalizedOffset(indexed, .acousticResult) == 2.1)
    }

    @Test
    func noSustains() {
        let indexed = pair(offset: 3, next: 2, sustains: [])
        #expect(normalizedOffset(indexed, .acousticResult) == 3)
        #expect(normalizedOffset(indexed, .notesDisplay) == 2)
    }

    /// The rules never make a note shorter than 0.1 beat, but the note still ends before the next note on its key.
    @Test
    func minimumLengthAndTheNextNoteOnTheKey() {
        let indexed = track([note(0, 3, 60), note(0.08, 1, 60)], sustains: [MIDISustainEvent(onset: 0, offset: 5)])
        let result = indexed.normalizing(preserve: .acousticResult)
        #expect(result.notes[0].offset == 0.08.nextDown)
        #expect(result.notes[1] == indexed.notes[1]) // the last chord is kept
    }

    @Test(arguments: 0..<5)
    func keepsEverythingButOffsets(seed: Int) {
        let notes = cleanInput(seed: UInt64(seed) &+ 900, count: 150)
        let source = MIDITrack(
            notes: notes,
            sustains: randomSustains(seed: UInt64(seed), end: 20),
            metaEvents: [MIDIMetaEvent(timestamp: 1, type: 1, data: Data([1]))],
            channelEvents: MIDIChannelEvents([MIDIChannelEvent(onset: 0.5, message: .controlChange(controller: 0, value: 64))])
        )
        let indexed = IndexedTrack(MIDIContainer(tracks: [source]))
        let result = indexed.normalizing(preserve: .notesDisplay)

        #expect(result.notes.map(\.onset) == indexed.notes.map(\.onset))
        #expect(result.notes.map(\.pitch) == indexed.notes.map(\.pitch))
        #expect(result.sustains == indexed.sustains)
        #expect(result.channelEvents == indexed.channelEvents)
        #expect(result.metaEvents == indexed.metaEvents)
        #expect(result.profile is GenericProfile)

        let fresh = IndexedTrack(validated: result.notes, sustains: result.sustains, channelEvents: result.channelEvents, metaEvents: result.metaEvents, rawData: result.rawData, profile: result.profile)
        #expect(result.lanes.members == fresh.lanes.members)
        #expect(result.lanes.starts == fresh.lanes.starts)
    }

    /// The new enum must decode the raw values of the old one, in the same order, until the old one is removed.
    @Test
    func preserveSettingsMatchTheOldOnes() {
        #expect(IndexedTrack.PreserveSettings.allCases.map(\.rawValue) == IndexedContainer.PreserveSettings.allCases.map(\.rawValue))
    }

    @Test
    func edgeCases() {
        #expect(track([]).normalizing(preserve: .notesDisplay).notes.isEmpty)

        // A single chord is the last chord, so only the final pass applies.
        let chord = track([note(0, 3, 60), note(0, 3, 64)], sustains: [MIDISustainEvent(onset: 0, offset: 1)])
        #expect(chord.normalizing(preserve: .notesDisplay).notes == chord.notes)
    }

}
