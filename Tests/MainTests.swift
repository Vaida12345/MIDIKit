//
//  MainTests.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

@testable
import MIDIKit
import Testing


@Suite
struct DistanceTests {
    
    @Test func empty() async throws {
        let lhs = MIDITrack()
        let rhs = MIDITrack()
        #expect(lhs.notes.distance(to: rhs.notes) == 0)
    }
    
    @Test func simple() async throws {
        let lhs = MIDITrack(notes: [.init(onset: 1, offset: 2, note: 3, velocity: 4, channel: 0)])
        let rhs = MIDITrack()
        #expect(lhs.notes.distance(to: rhs.notes) == 10)
    }
    
    @Test func simpleWithMatch() async throws {
        let lhs = MIDITrack(notes: [.init(onset: 1, offset: 2, note: 3, velocity: 4, channel: 0)])
        let rhs = MIDITrack(notes: [.init(onset: 1.1, offset: 2.1, note: 3, velocity: 4, channel: 0), .init(onset: 2, offset: 2, note: 3, velocity: 4, channel: 0)])
        #expect(lhs.notes.distance(to: rhs.notes) == 0.1 + 10)
    }
    
    @Test func determineNote() {
        print(MIDINote.determine(note: 60))
    }
    
}
