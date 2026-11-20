//
//  IndexedTrackTests.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import Testing
import Foundation
import MIDIKit
import Intervals
@testable
import IndexedTrack


// MARK: - Support

private let gap = 1.0 / 128

private func note(_ onset: Double, _ offset: Double, _ pitch: UInt8, velocity: UInt8 = 80) -> MIDINote {
    MIDINote(onset: onset, offset: offset, note: pitch, velocity: velocity)
}

private func track(_ notes: [MIDINote], sustains: [MIDISustainEvent] = []) -> IndexedTrack {
    IndexedTrack(MIDIContainer(tracks: [MIDITrack(notes: notes, sustains: sustains)]))
}


/// A small deterministic generator, so the figures never change.
private struct TestRNG {
    
    var state: UInt64
    
    init(seed: UInt64) {
        self.state = seed &* 0x9E3779B97F4A7C15 &+ 0x1234567
    }
    
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    
    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }
    
}


/// Random notes that need no cleanup rule that changed from `IndexedContainer`: pitches in range, valid times, and same-key onsets never closer than the gap. Notes may still overlap on the same key, so trimming is exercised.
private func cleanInput(seed: UInt64, count: Int) -> [MIDINote] {
    var rng = TestRNG(seed: seed)
    var notes: [MIDINote] = []
    var lastOnsets: [UInt8: Double] = [:]
    var time = 0.0
    while notes.count < count {
        time += Double(rng.int(0...4)) / 16
        let pitch = UInt8(rng.int(48...72))
        guard lastOnsets[pitch] != time else { continue } // a step of 0 could repeat a key at the same onset, a double trigger
        lastOnsets[pitch] = time
        let duration = Double(rng.int(1...24)) / 16
        notes.append(note(time, time + duration, pitch, velocity: UInt8(rng.int(1...127))))
    }
    return notes.shuffled(using: &rng)
}

extension TestRNG: RandomNumberGenerator { }


private func isOrdered(_ lhs: MIDINote, _ rhs: MIDINote) -> Bool {
    lhs.onset < rhs.onset || (lhs.onset == rhs.onset && lhs.pitch < rhs.pitch)
}


// MARK: - Tests

@Suite(.timeLimit(.minutes(1)))
struct IndexedTrackTests {
    
    @Test
    func dropsInvalidNotes() {
        let indexed = track([
            note(0, 1, 20), // below the keyboard
            note(0, 1, 109), // above the keyboard
            note(1, 0.5, 60), // ends before it starts
            note(.nan, 1, 61),
            note(0, .infinity, 62),
            note(2, 3, 64),
        ])
        #expect(indexed.notes == [note(2, 3, 64)])
    }
    
    @Test
    func mergesDoubleTriggers() {
        let indexed = track([
            note(0, 0.5, 60, velocity: 40),
            note(0.005, 0.8, 60, velocity: 90), // closer than the gap
        ])
        #expect(indexed.notes == [note(0, 0.8, 60, velocity: 90)])
    }
    
    @Test
    func trimsBeforeTheNextNote() {
        let indexed = track([
            note(0, 1, 60),
            note(0.5, 1, 60),
        ])
        #expect(indexed.notes == [note(0, 0.5 - gap, 60), note(0.5, 1, 60)])
    }
    
    @Test
    func dropsNotesTooShortAfterTrimming() {
        let indexed = track([
            note(0, 1, 60),
            note(0.01, 1, 60), // farther than the gap, but leaves the first note shorter than it
        ])
        #expect(indexed.notes == [note(0.01, 1, 60)])
    }
    
    @Test
    func sortsByOnsetThenPitch() {
        let indexed = track([
            note(1, 2, 64),
            note(1, 2, 60),
            note(0, 2, 72),
        ])
        #expect(indexed.notes.map(\.pitch) == [72, 60, 64])
    }
    
    @Test
    func mergesTracksKeepingChannels() {
        let container = MIDIContainer(tracks: [
            MIDITrack(notes: [MIDINote(onset: 0, offset: 1, note: 60, velocity: 80, channel: 3), note(0, 1, 62)]),
            MIDITrack(notes: [MIDINote(onset: 0, offset: 1, note: 64, velocity: 80, channel: 5)]),
        ])
        let indexed = IndexedTrack(container)
        #expect(indexed.notes.map(\.pitch) == [60, 62, 64])
        #expect(indexed.notes.map(\.channel) == [3, 0, 5])
    }
    
    @Test
    func mergesSustains() {
        let indexed = track([], sustains: [
            MIDISustainEvent(onset: 3, offset: 4),
            MIDISustainEvent(onset: 1, offset: 2), // touches the first
            MIDISustainEvent(onset: 0, offset: 1),
            MIDISustainEvent(onset: 6, offset: 5), // ends before it starts
        ])
        #expect(indexed.sustains == [MIDISustainEvent(onset: 0, offset: 2), MIDISustainEvent(onset: 3, offset: 4)])
    }
    
    /// At 60 BPM, a beat lasts twice as long as at 120 BPM, so every time doubles.
    @Test
    func convertsTempo() {
        let source = MIDITrack(
            notes: [note(1, 2, 60)],
            sustains: [MIDISustainEvent(onset: 1, offset: 3)],
            metaEvents: [MIDIMetaEvent(timestamp: 1.5, type: 1, data: Data([1]))],
            controlEvents: MIDIControlEvents([MIDIControlEvent(onset: 2.5, channel: 0, velocity: 64)])
        )
        let container = MIDIContainer(tracks: [source], tempo: MIDITempoTrack(tempos: [MIDITempoTrack.Tempo(timestamp: 0, tempo: 60)]))
        let indexed = IndexedTrack(container)
        
        #expect(indexed.notes == [note(2, 4, 60)])
        #expect(indexed.sustains == [MIDISustainEvent(onset: 2, offset: 6)])
        #expect(indexed.metaEvents.map(\.timestamp) == [3])
        #expect(indexed.controlEvents.map(\.onset) == [5])
    }
    
    @Test
    func roundTrip() {
        let indexed = track(cleanInput(seed: 1, count: 300))
        let again = IndexedTrack(indexed.makeContainer())
        #expect(again.notes == indexed.notes)
        #expect(again.sustains == indexed.sustains)
    }
    
    /// The initializer for validated input keeps everything as given, and builds the lanes on first use.
    @Test
    func validatedInitializer() {
        let source = MIDITrack(
            notes: cleanInput(seed: 2, count: 100),
            sustains: [MIDISustainEvent(onset: 0, offset: 2), MIDISustainEvent(onset: 3, offset: 5)],
            metaEvents: [MIDIMetaEvent(timestamp: 1, type: 1, data: Data([1]))],
            controlEvents: MIDIControlEvents([MIDIControlEvent(onset: 0.5, channel: 0, velocity: 64)])
        )
        let indexed = IndexedTrack(MIDIContainer(tracks: [source]))
        let validated = IndexedTrack(validated: indexed.notes, sustains: indexed.sustains, controlEvents: indexed.controlEvents, metaEvents: indexed.metaEvents, profile: indexed.profile)
        
        #expect(validated.notes == indexed.notes)
        #expect(validated.sustains == indexed.sustains)
        #expect(validated.controlEvents == indexed.controlEvents)
        #expect(validated.metaEvents == indexed.metaEvents)
        #expect(validated.lanes.members == indexed.lanes.members)
        #expect(validated.lanes.starts == indexed.lanes.starts)
    }
    
    /// On input that needs none of the changed rules, the notes are the same as `IndexedContainer`'s.
    @Test(arguments: 0..<20)
    func matchesIndexedContainer(seed: Int) {
        let notes = cleanInput(seed: UInt64(seed), count: 200)
        let container = MIDIContainer(tracks: [MIDITrack(notes: notes)])
        
        let indexed = IndexedTrack(container)
        let expected = IndexedContainer(container: container).makeContainer().tracks[0].notes.contents.sorted(by: isOrdered)
        #expect(indexed.notes == expected)
    }
    
    @Test(arguments: 0..<10)
    func lanes(seed: Int) {
        let indexed = track(cleanInput(seed: UInt64(seed) &+ 100, count: 300))
        let lanes = indexed.lanes
        
        var seen = Set<Int>()
        for pitch in 21...108 as ClosedRange<UInt8> {
            let lane = lanes[lane: pitch]
            #expect(lane.allSatisfy { $0.pitch == pitch })
            #expect(lane.isValidDisjointIntervals())
            for position in lane.indices {
                let index = lane.noteIndex(at: position)
                #expect(indexed.notes[index] == lane[position])
                seen.insert(index)
            }
        }
        #expect(seen == Set(indexed.notes.indices))
        
        // The lanes stored by the initializer equal the ones the lazy path builds.
        let fresh = IndexedTrack(validated: indexed.notes, sustains: indexed.sustains, controlEvents: indexed.controlEvents, metaEvents: indexed.metaEvents, profile: indexed.profile)
        let lazy = fresh.lanes
        #expect(lazy.members == lanes.members)
        #expect(lazy.starts == lanes.starts)
    }
    
    @Test
    func intervalTree() {
        let indexed = track(cleanInput(seed: 7, count: 300))
        let tree = indexed.intervalTree
        let end = Int((indexed.notes.map(\.offset).max() ?? 0) * 16) + 16
        for step in -16...end {
            let time = Double(step) / 16
            let expected = indexed.notes.indices.filter { indexed.notes[$0].onset <= time && indexed.notes[$0].offset >= time }
            #expect(tree.indices(containing: time) == expected, "time: \(time)")
        }
    }
    
}
