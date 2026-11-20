//
//  IndexedSustainsTests.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import Testing
import MIDIKit
@testable
import IndexedTrack


@Suite(.timeLimit(.minutes(1)))
struct IndexedSustainsTests {

    @Test
    func cleansUp() {
        let sustains = IndexedTrack.Sustains([
            MIDISustainEvent(onset: 3, offset: 4),
            MIDISustainEvent(onset: 1, offset: 2), // touches the next one
            MIDISustainEvent(onset: 0, offset: 1),
            MIDISustainEvent(onset: 1.5, offset: 1.8), // inside another
            MIDISustainEvent(onset: 6, offset: 5), // ends before it starts
            MIDISustainEvent(onset: .nan, offset: 7),
            MIDISustainEvent(onset: 8, offset: .infinity),
        ])
        let gap = 1.0 / 128
        // The touching pair stays apart, and the sustain inside splits the one around it, which stays down until 2.
        #expect(sustains.contents == [MIDISustainEvent(onset: 0, offset: 1 - gap), MIDISustainEvent(onset: 1, offset: 1.5 - gap), MIDISustainEvent(onset: 1.5, offset: 2), MIDISustainEvent(onset: 3, offset: 4)])
        #expect(sustains.isValidDisjointIntervals())
    }

    @Test
    func empty() {
        let sustains = IndexedTrack.Sustains([])
        #expect(sustains.isEmpty)
        #expect(sustains.index(at: 0) == nil)
        #expect(sustains.firstIndex(after: 0) == nil)
    }

    @Test
    func queries() {
        let sustains = IndexedTrack.Sustains(validated: [MIDISustainEvent(onset: 0, offset: 2), MIDISustainEvent(onset: 3, offset: 4), MIDISustainEvent(onset: 6, offset: 8)])

        #expect(sustains.index(at: 0) == 0) // bounds are inclusive
        #expect(sustains.index(at: 2) == 0)
        #expect(sustains.index(at: 2.5) == nil)
        #expect(sustains.index(at: 7) == 2)
        #expect(sustains[at: 3.5] == MIDISustainEvent(onset: 3, offset: 4))

        #expect(sustains.firstIndex(after: 2.5) == 1)
        #expect(sustains.firstIndex(after: 6) == nil)
        #expect(sustains.first(after: -1) == MIDISustainEvent(onset: 0, offset: 2))
        #expect(sustains.lastIndex(before: 5) == 1)
        #expect(sustains.lastIndex(before: 1) == nil)
        #expect(sustains.indices(overlapping: 1...3) == 0..<2)
    }

    /// The track combines the sustains of every source track, keeping the pedal change.
    @Test
    func trackCombinesSustains() {
        let container = MIDIContainer(tracks: [
            MIDITrack(notes: [], sustains: [MIDISustainEvent(onset: 0, offset: 1)]),
            MIDITrack(notes: [], sustains: [MIDISustainEvent(onset: 0.5, offset: 2)]),
        ])
        #expect(IndexedTrack(container).sustains.contents == [MIDISustainEvent(onset: 0, offset: 0.5 - 1.0 / 128), MIDISustainEvent(onset: 0.5, offset: 2)])
    }

    /// The track uses its minimum gap between consecutive notes as the gap between sustains.
    @Test
    func usesMinimumConsecutiveNotesGap() {
        let container = MIDIContainer(tracks: [
            MIDITrack(notes: [], sustains: [MIDISustainEvent(onset: 0, offset: 1)]),
            MIDITrack(notes: [], sustains: [MIDISustainEvent(onset: 1, offset: 2)]),
        ])
        #expect(IndexedTrack(container, minimumConsecutiveNotesGap: 1 / 16).sustains.contents == [MIDISustainEvent(onset: 0, offset: 1 - 1 / 16), MIDISustainEvent(onset: 1, offset: 2)])
    }

}
