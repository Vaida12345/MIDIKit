//
//  MergingNotesInSameIntervalTests.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-23.
//

import Testing
import Foundation
import MIDIKit
@testable
import IndexedTrack


// MARK: - Support

/// A profile that implements only the required hooks.
private struct ChordsOnly: AnalysisProfile {
    func formChords(in track: IndexedTrack) -> IndexedTrack.Chords {
        ChordArbiter.generic.formChords(in: track)
    }
}

/// The rule of MIDIKit 1.x, written plainly: on each key, a note joins the note before it when both centers are in the same reference note and it is quiet enough.
private func model(_ notes: [MIDINote], reference: [MIDINote], threshold: UInt8, difference: UInt8) -> [MIDINote] {
    var result: [MIDINote] = []
    for pitch in 21...108 as ClosedRange<UInt8> {
        let lane = notes.filter { $0.pitch == pitch }
        let referenceLane = reference.filter { $0.pitch == pitch }
        func interval(of note: MIDINote) -> Int? {
            let center = note.onset + note.duration / 2
            return referenceLane.firstIndex { $0.onset <= center && center <= $0.offset }
        }

        guard var previous = lane.first else { continue }
        var previousInterval = interval(of: previous)
        for current in lane.dropFirst() {
            let currentInterval = interval(of: current)
            let ceiling = Int(previous.velocity) - Int(difference)
            if let currentInterval, currentInterval == previousInterval, current.velocity <= threshold, Int(current.velocity) <= max(ceiling, 0) {
                previous.offset = current.offset
            } else {
                result.append(previous)
                previous = current
                previousInterval = currentInterval
            }
        }
        result.append(previous)
    }
    return result.sorted(by: isOrdered)
}

/// A reference of random held notes, and a track that breaks each of them into one to three fragments of random velocities.
private func fragmentedPair(seed: UInt64) -> (fragments: IndexedTrack, reference: IndexedTrack) {
    let reference = track(cleanInput(seed: seed, count: 200))
    var rng = IndexedTrackRNG(seed: seed &+ 99)
    var fragments: [MIDINote] = []
    for note in reference.notes {
        let count = rng.int(1...3)
        let length = note.duration / Double(count)
        for index in 0..<count {
            let onset = note.onset + Double(index) * length
            // Shorter than its share, so the fragments are apart; sometimes it spills past the reference note.
            let offset = onset + length * (rng.int(0...3) == 0 ? 1.4 : 0.8)
            fragments.append(MIDINote(onset: onset, offset: offset, pitch: note.pitch, velocity: UInt8(rng.int(1...127))))
        }
    }
    return (track(fragments), reference)
}


// MARK: - Tests

@Suite(.timeLimit(.minutes(1)))
struct MergingNotesInSameIntervalTests {

    /// The test of MIDIKit 1.x.
    @Test
    func mergesFragmentsOfOneNote() {
        let indexed = track([note(0, 1, 60, velocity: 10), note(2, 3, 60, velocity: 10)])
        let reference = track([note(0, 3, 60, velocity: 10)])
        #expect(indexed.mergingNotesInSameInterval(of: reference, threshold: 70, difference: 0).notes == [note(0, 3, 60, velocity: 10)])
    }

    @Test
    func mergesAChainIntoTheFirstNote() {
        let indexed = track([note(0, 1, 60, velocity: 90), note(1.5, 2, 60, velocity: 30), note(2.5, 3, 60, velocity: 20)])
        let reference = track([note(0, 3, 60)])
        #expect(indexed.mergingNotesInSameInterval(of: reference, threshold: 70, difference: 5).notes == [note(0, 3, 60, velocity: 90)])
    }

    /// The note before a fragment is compared by its own center, not by the center of what it absorbed.
    @Test
    func chainKeepsTheFirstCenter() {
        let indexed = track([note(0, 1, 60, velocity: 90), note(1.5, 2, 60, velocity: 30), note(4.5, 5, 60, velocity: 20)])
        let reference = track([note(0, 3, 60), note(4, 6, 60)])
        #expect(indexed.mergingNotesInSameInterval(of: reference, threshold: 70, difference: 5).notes == [note(0, 2, 60, velocity: 90), note(4.5, 5, 60, velocity: 20)])
    }

    @Test
    func keepsNotesInDifferentReferenceNotes() {
        let indexed = track([note(0, 1, 60, velocity: 10), note(2, 3, 60, velocity: 10)])
        let reference = track([note(0, 1.5, 60), note(1.75, 3, 60)])
        #expect(indexed.mergingNotesInSameInterval(of: reference, threshold: 70, difference: 0).notes == indexed.notes)
    }

    @Test
    func keepsNotesOutsideTheReference() {
        let indexed = track([note(0, 1, 60, velocity: 10), note(2, 3, 60, velocity: 10)])
        // The second center, 2.5, is in no reference note; then neither center is, and two notes in no reference note are not in the same one.
        #expect(indexed.mergingNotesInSameInterval(of: track([note(0, 2, 60)]), threshold: 70, difference: 0).notes == indexed.notes)
        #expect(indexed.mergingNotesInSameInterval(of: track([note(0.6, 2.4, 60)]), threshold: 70, difference: 0).notes == indexed.notes)
    }

    /// A center on the bound of a reference note is in it.
    @Test
    func boundsAreInclusive() {
        let indexed = track([note(0, 1, 60, velocity: 50), note(2, 3, 60, velocity: 10)])
        let reference = track([note(0.5, 2.5, 60)])
        #expect(indexed.mergingNotesInSameInterval(of: reference, threshold: 70, difference: 0).notes == [note(0, 3, 60, velocity: 50)])
    }

    @Test
    func keepsLoudNotes() {
        let indexed = track([note(0, 1, 60, velocity: 50), note(2, 3, 60, velocity: 71)])
        let reference = track([note(0, 3, 60)])
        #expect(indexed.mergingNotesInSameInterval(of: reference, threshold: 70, difference: 0).notes == indexed.notes)

        // A new key press, louder than the note before it.
        let restruck = track([note(0, 1, 60, velocity: 30), note(2, 3, 60, velocity: 50)])
        #expect(restruck.mergingNotesInSameInterval(of: reference, threshold: 70, difference: 0).notes == restruck.notes)
    }

    @Test
    func differenceIsInclusive() {
        let reference = track([note(0, 3, 60)])
        let justEnough = track([note(0, 1, 60, velocity: 50), note(2, 3, 60, velocity: 45)])
        #expect(justEnough.mergingNotesInSameInterval(of: reference, threshold: 70, difference: 5).notes == [note(0, 3, 60, velocity: 50)])

        let tooLoud = track([note(0, 1, 60, velocity: 50), note(2, 3, 60, velocity: 46)])
        #expect(tooLoud.mergingNotesInSameInterval(of: reference, threshold: 70, difference: 5).notes == tooLoud.notes)
    }

    /// MIDIKit 1.x trapped on `prev.velocity - difference` here.
    @Test
    func differenceGreaterThanVelocityDoesNotTrap() {
        let reference = track([note(0, 3, 60)])
        let quiet = track([note(0, 1, 60, velocity: 20), note(2, 3, 60, velocity: 10)])
        #expect(quiet.mergingNotesInSameInterval(of: reference, threshold: 70, difference: 30).notes == quiet.notes)

        let silent = track([note(0, 1, 60, velocity: 20), note(2, 3, 60, velocity: 0)])
        #expect(silent.mergingNotesInSameInterval(of: reference, threshold: 70, difference: 30).notes == [note(0, 3, 60, velocity: 20)])
    }

    @Test
    func keysAreIndependent() {
        let pair: [UInt8] = [60, 62, 64]
        let indexed = track(pair.flatMap { [note(0, 1, $0, velocity: 50), note(2, 3, $0, velocity: 10)] })
        // Only the reference note on 60 holds both fragments: 62 has two reference notes, 64 none, and the one on 65 is on another key.
        let reference = track([note(0, 3, 60), note(0, 1.5, 62), note(1.75, 3, 62), note(0, 3, 65)])
        #expect(indexed.mergingNotesInSameInterval(of: reference, threshold: 70, difference: 0).notes == [note(0, 3, 60, velocity: 50), note(0, 1, 62, velocity: 50), note(0, 1, 64, velocity: 50), note(2, 3, 62, velocity: 10), note(2, 3, 64, velocity: 10)])
    }

    @Test
    func emptyTracks() {
        let indexed = track([note(0, 1, 60, velocity: 10), note(2, 3, 60, velocity: 10)])
        #expect(indexed.mergingNotesInSameInterval(of: track([]), threshold: 127, difference: 0).notes == indexed.notes)
        #expect(track([]).mergingNotesInSameInterval(of: indexed, threshold: 127, difference: 0).notes.isEmpty)
    }

    @Test
    func keepsEverythingButNotes() {
        let source = MIDITrack(
            notes: [note(0, 1, 60, velocity: 50), note(2, 3, 60, velocity: 10)],
            sustains: [MIDISustainEvent(onset: 1, offset: 3), MIDISustainEvent(onset: 4, offset: 6)],
            metaEvents: [MIDIMetaEvent(timestamp: 1, type: 1, data: Data([1]))],
            channelEvents: MIDIChannelEvents([MIDIChannelEvent(onset: 0.5, message: .controlChange(controller: 0, value: 64))])
        )
        let indexed = IndexedTrack(MIDIContainer(tracks: [source]), profile: ChordsOnly())
        let result = indexed.mergingNotesInSameInterval(of: track([note(0, 3, 60)]), threshold: 70, difference: 0)

        #expect(result.notes == [note(0, 3, 60, velocity: 50)])
        #expect(result.sustains == indexed.sustains)
        #expect(result.channelEvents == indexed.channelEvents)
        #expect(result.metaEvents == indexed.metaEvents)
        #expect(result.rawData == indexed.rawData)
        #expect(result.profile is ChordsOnly)
    }

    @Test(arguments: 0..<20)
    func matchesTheRuleOfMIDIKit1(seed: Int) {
        let (fragments, reference) = fragmentedPair(seed: UInt64(seed) &+ 2_100)
        for (threshold, difference) in [(70, 5), (127, 0), (40, 20), (127, 127)] as [(UInt8, UInt8)] {
            let result = fragments.mergingNotesInSameInterval(of: reference, threshold: threshold, difference: difference)
            #expect(result.notes == model(fragments.notes, reference: reference.notes, threshold: threshold, difference: difference))
            #expect(IndexedTrack.isValid(notes: result.notes, lanes: result.lanes))
            #expect(result.notes.count <= fragments.notes.count)
        }
        #expect(fragments.mergingNotesInSameInterval(of: reference, threshold: 127, difference: 0).notes.count < fragments.notes.count)
    }

    /// Against unrelated random notes, so centers also fall between reference notes and on other keys.
    @Test(arguments: 0..<10)
    func matchesTheRuleOfMIDIKit1OnUnrelatedTracks(seed: Int) {
        let indexed = track(cleanInput(seed: UInt64(seed) &+ 2_300, count: 300))
        let reference = track(cleanInput(seed: UInt64(seed) &+ 2_400, count: 300))
        let result = indexed.mergingNotesInSameInterval(of: reference, threshold: 90, difference: 3)
        #expect(result.notes == model(indexed.notes, reference: reference.notes, threshold: 90, difference: 3))
    }

}
