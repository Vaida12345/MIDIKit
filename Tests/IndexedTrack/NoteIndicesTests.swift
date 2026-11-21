//
//  NoteIndicesTests.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-21.
//

import Testing
import Foundation
import MIDIKit
@testable
import IndexedTrack


@Suite(.timeLimit(.minutes(1)))
struct NoteIndicesTests {
    
    /// A note index reaches in the track's notes the note at the same position in the lane or the chord.
    @Test(arguments: 0..<5)
    func noteIndicesReachTheSameNotes(seed: Int) {
        let indexed = track(cleanInput(seed: UInt64(seed) &+ 400, count: 300))
        for lane in indexed.lanes {
            #expect(lane.noteIndices.count == lane.count)
            for position in lane.indices {
                #expect(indexed.notes[lane.noteIndices[position]] == lane[position])
            }
            #expect(lane.noteIndices.map { indexed.notes[$0] } == Array(lane))
        }
        for chord in indexed.chords {
            for position in chord.indices {
                #expect(indexed.notes[chord.noteIndices[position]] == chord[position])
            }
        }
    }
    
    /// Positions start at 0 for every lane, though the lanes share their storage.
    @Test
    func positionsStartAtZero() throws {
        let indexed = track([note(0, 1, 60), note(1, 2, 62), note(2, 3, 62)])
        let lane = indexed.lanes[62]
        #expect(lane.noteIndices.startIndex == 0)
        #expect(Array(lane.noteIndices) == [1, 2])
        #expect(lane.noteIndices[0] == 1)
    }
    
    @Test
    func lanesAreTheKeys() {
        let indexed = track(cleanInput(seed: 9, count: 200))
        let lanes = indexed.lanes
        #expect(lanes.count == 88)
        #expect(Array(lanes.indices) == Array(21...108))
        #expect(lanes.map(\.count).reduce(0, +) == indexed.notes.count)
        #expect(zip(lanes, lanes.indices).allSatisfy { lane, key in lane.allSatisfy { $0.pitch == key } })
    }
    
    @Test
    func modifyingNotesKeepsEverythingElse() {
        let source = MIDITrack(
            notes: [note(0, 1, 60), note(2, 3, 60), note(0, 2, 64)],
            sustains: [MIDISustainEvent(onset: 0, offset: 1.5)],
            metaEvents: [MIDIMetaEvent(timestamp: 0.5, type: 0x06, data: Data("marker".utf8))],
            channelEvents: MIDIChannelEvents([MIDIChannelEvent(onset: 0, message: .programChange(program: 3))])
        )
        let indexed = IndexedTrack(MIDIContainer(tracks: [source]), profile: .transkun)
        let lane = indexed.lanes[60]
        let modified = indexed.modifyingNotes { notes in
            notes[lane.noteIndices[0]].offset = 0.5
            for index in notes.indices { notes[index].velocity = 40 }
        }
        
        #expect(modified.notes.map(\.offset) == [0.5, 2, 3])
        #expect(modified.notes.allSatisfy { $0.velocity == 40 })
        #expect(modified.notes.map(\.onset) == indexed.notes.map(\.onset))
        #expect(modified.sustains == indexed.sustains)
        #expect(modified.channelEvents == indexed.channelEvents)
        #expect(modified.metaEvents == indexed.metaEvents)
        #expect(modified.profile is TranskunProfile)
        #expect(Array(modified.lanes[60].noteIndices) == Array(lane.noteIndices))
    }
    
    @Test
    func modifyingNothingKeepsTheNotes() {
        let indexed = track(cleanInput(seed: 4, count: 200))
        let same = indexed.modifyingNotes { _ in }
        #expect(same.notes == indexed.notes)
        #expect(same.lanes.members == indexed.lanes.members)
        #expect(same.lanes.starts == indexed.lanes.starts)
    }
    
}
