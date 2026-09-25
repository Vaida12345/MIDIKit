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
    
    /// Verifies identical scores have no normalized difference.
    @Test func normalizedDistanceIsZeroForIdenticalScores() {
        let notes = [MIDINote(onset: 1, offset: 2, note: 3, velocity: 4, channel: 0)]
        let lhs = MIDITrack(notes: notes)
        let rhs = MIDITrack(notes: notes)
        
        #expect(lhs.notes.normalizedDistance(to: rhs.notes) == 0)
    }
    
    /// Verifies scores without matching pitches reach the maximum normalized difference.
    @Test func normalizedDistanceIsOneForScoresWithoutMatchingPitches() {
        let lhs = MIDITrack(notes: [.init(onset: 1, offset: 2, note: 3, velocity: 4, channel: 0)])
        let rhs = MIDITrack(notes: [.init(onset: 1, offset: 2, note: 4, velocity: 4, channel: 0)])
        
        #expect(lhs.notes.normalizedDistance(to: rhs.notes) == 1)
    }
    
    /// Verifies timing differences contribute proportionally to the normalized difference.
    @Test func normalizedDistanceAccountsForTimingError() {
        let lhs = MIDITrack(notes: [.init(onset: 1, offset: 2, note: 3, velocity: 4, channel: 0)])
        let rhs = MIDITrack(notes: [.init(onset: 2, offset: 3, note: 3, velocity: 4, channel: 0)])
        
        #expect(abs(lhs.notes.normalizedDistance(to: rhs.notes) - 0.05) < 0.000_001)
    }
    
    @Test func determineNote() {
        print(MIDINote.determine(note: 60))
    }
    
}
