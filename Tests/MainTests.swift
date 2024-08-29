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
        await #expect(lhs.notes.distance(to: rhs.notes) == 0)
    }
    
    @Test func simple() async throws {
        let lhs = MIDITrack(notes: [.init(onset: 1, offset: 2, note: 3, velocity: 4, channel: 0)])
        let rhs = MIDITrack()
        await #expect(lhs.notes.distance(to: rhs.notes) == 10)
    }
    
    @Test func simpleWithMatch() async throws {
        let lhs = MIDITrack(notes: [.init(onset: 1, offset: 2, note: 3, velocity: 4, channel: 0)])
        let rhs = MIDITrack(notes: [.init(onset: 1.1, offset: 2.1, note: 3, velocity: 4, channel: 0), .init(onset: 2, offset: 2, note: 3, velocity: 4, channel: 0)])
        await #expect(lhs.notes.distance(to: rhs.notes) == 0.1 + 10)
    }
    
    @Test func notesClustering() async throws {
        let notes = MIDINotes(notes: [0.1, 0.12, 0.15, 0.23, 0.28, 0.3, 0.5].map {
            MIDINote(onset: $0, offset: 10, note: 10, velocity: 10, channel: 0)
        })
        
        let clusters = notes.clustered(threshold: 0.05)
        
        #expect(clusters.map { $0.map(\.onset) } == [[0.1, 0.12, 0.15], [0.23], [0.28, 0.3], [0.5]])
    }
    
}
