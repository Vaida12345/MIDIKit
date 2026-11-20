//
//  ApplyingGapTests.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import Testing
import Foundation
import MIDIKit
@testable
import IndexedTrack


/// The rules of `IndexedContainer.applyGap`, one branch per case, with its clamp fixed to `onset + minimumNoteLength`.
private func expectedGap(_ notes: [MIDINote], ideal: Double, minimumNoteLength: Double) -> [MIDINote] {
    var notes = notes
    for pitch in 21...108 as ClosedRange<UInt8> {
        let lane = notes.indices.filter { notes[$0].pitch == pitch } // in onset order, as the notes are
        for (current, next) in zip(lane, lane.dropFirst()) {
            let gap = notes[next].onset - notes[current].offset
            let distance = notes[next].onset - notes[current].onset
            guard gap <= ideal else { continue }
            if distance > 2 * ideal {
                notes[current].offset = notes[next].onset - ideal
            } else if distance > minimumNoteLength {
                notes[current].offset = Swift.max(notes[next].onset - ideal, notes[current].onset + minimumNoteLength)
            }
        }
    }
    return notes
}


@Suite(.timeLimit(.minutes(1)))
struct ApplyingGapTests {

    @Test
    func keepsLargeGaps() {
        let indexed = track([note(0, 1, 60), note(1.5, 2, 60)])
        #expect(indexed.applyingGap().notes == indexed.notes)
    }

    @Test
    func endsIdealBeforeTheNextNote() {
        let indexed = track([note(0, 0.95, 60), note(1, 2, 60)])
        #expect(indexed.applyingGap().notes == [note(0, 1 - 1/8, 60), note(1, 2, 60)])
    }

    @Test
    func keepsTheMinimumLength() {
        let indexed = track([note(10, 10.1, 60), note(10.12, 11, 60)])
        #expect(indexed.applyingGap().notes == [note(10, 10 + 1/128, 60), note(10.12, 11, 60)])
    }

    @Test
    func keepsNotesTooCloseToShorten() {
        let indexed = track([note(10, 10.1, 60), note(10.2, 11, 60)])
        #expect(indexed.applyingGap(minimumNoteLength: 0.25).notes == indexed.notes)
    }

    @Test
    func changesOnlyNotesFollowedOnTheSameKey() {
        let indexed = track([note(0, 0.95, 60), note(0, 0.95, 62), note(1, 2, 60)])
        #expect(indexed.applyingGap().notes == [note(0, 1 - 1/8, 60), note(0, 0.95, 62), note(1, 2, 60)])
    }

    /// `IndexedContainer.applyGap` clamped the offset to `duration + minimumNoteLength`, a length rather than a time, which near 0 made this note overlap the next.
    @Test
    func clampsToATimeNotALength() {
        let indexed = track([note(0, 0.205, 60), note(0.21, 1, 60)])
        let result = indexed.applyingGap()
        #expect(result.notes == [note(0, 0.21 - 1/8, 60), note(0.21, 1, 60)])
        #expect(result.notes[0].offset < result.notes[1].onset)
    }

    /// The single branchless expression equals the rules of `IndexedContainer.applyGap`, case by case.
    @Test(arguments: 0..<20)
    func matchesTheBranchedRules(seed: Int) {
        let indexed = track(cleanInput(seed: UInt64(seed) &+ 200, count: 300))
        let parameters: [(ideal: Double, minimumNoteLength: Double)] = [(0.125, 0.0078125), (0.25, 0.0625), (0.0625, 0.015625)]
        for (ideal, minimumNoteLength) in parameters {
            let result = indexed.applyingGap(ideal: ideal, minimumNoteLength: minimumNoteLength)
            #expect(result.notes == expectedGap(indexed.notes, ideal: ideal, minimumNoteLength: minimumNoteLength), "ideal: \(ideal), minimumNoteLength: \(minimumNoteLength)")
        }
    }

    @Test(arguments: 0..<10)
    func reusesTheLanesLayout(seed: Int) {
        let result = track(cleanInput(seed: UInt64(seed) &+ 300, count: 300)).applyingGap()
        let fresh = IndexedTrack(validated: result.notes, sustains: result.sustains, channelEvents: result.channelEvents, metaEvents: result.metaEvents, profile: result.profile)
        #expect(result.lanes.members == fresh.lanes.members)
        #expect(result.lanes.starts == fresh.lanes.starts)
        #expect(result.lanes.notes == result.notes)
    }

    @Test
    func isIdempotent() {
        let once = track(cleanInput(seed: 4, count: 300)).applyingGap()
        #expect(once.applyingGap().notes == once.notes)
    }

    @Test
    func keepsEventsAndProfile() {
        let source = MIDITrack(
            notes: cleanInput(seed: 5, count: 100),
            sustains: [MIDISustainEvent(onset: 0, offset: 2), MIDISustainEvent(onset: 3, offset: 5)],
            metaEvents: [MIDIMetaEvent(timestamp: 1, type: 1, data: Data([1]))],
            channelEvents: MIDIChannelEvents([MIDIChannelEvent(onset: 0.5, message: .controlChange(controller: 0, value: 64))])
        )
        let indexed = IndexedTrack(MIDIContainer(tracks: [source]))
        let result = indexed.applyingGap()
        #expect(result.sustains == indexed.sustains)
        #expect(result.channelEvents == indexed.channelEvents)
        #expect(result.metaEvents == indexed.metaEvents)
        #expect(result.profile is GenericProfile)
    }

}
