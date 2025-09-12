//
//  removeArtifacts.swift
//  MIDIKit
//
//  Created by Vaida on 2025-08-30.
//

import Testing
import MIDIKit
import FinderItem


@Suite
struct RemoveArtifactsTests {
    
    @Test func mockAllUnder() async throws {
        let container = MIDIContainer(notes: [
            MIDINote(onset: 0, offset: 1, note: 50, velocity: 20),
            MIDINote(onset: 1, offset: 1.1, note: 50, velocity: 20),
            MIDINote(onset: 1.1, offset: 1.3, note: 50, velocity: 20)
        ])
        let reduced = await container.indexed().removingArtifacts(threshold: 30).makeContainer()
        try #require(reduced._checkConsistency())
        
        #expect(reduced.tracks[0].notes.count == 1)
        #expect(reduced.tracks[0].notes == [MIDINote(onset: 0, offset: 1.3, note: 50, velocity: 20)])
    }
    
    @Test func mockAllUnderExceptFirst() async throws {
        let container = MIDIContainer(notes: [
            MIDINote(onset: 0, offset: 1, note: 50, velocity: 50),
            MIDINote(onset: 1, offset: 1.1, note: 50, velocity: 20),
            MIDINote(onset: 1.1, offset: 1.3, note: 50, velocity: 20)
        ])
        let reduced = await container.indexed().removingArtifacts(threshold: 30).makeContainer()
        try #require(reduced._checkConsistency())
        
        #expect(reduced.tracks[0].notes.count == 1)
        #expect(reduced.tracks[0].notes == [MIDINote(onset: 0, offset: 1.3, note: 50, velocity: 50)])
    }
    
    @Test func mockAllButSecond() async throws {
        let container = MIDIContainer(notes: [
            MIDINote(onset: 0, offset: 1, note: 50, velocity: 20),
            MIDINote(onset: 1.01, offset: 1.1, note: 50, velocity: 50),
            MIDINote(onset: 1.1, offset: 1.3, note: 50, velocity: 20),
            MIDINote(onset: 1.3, offset: 1.5, note: 50, velocity: 20)
        ])
        let reduced = await container.indexed().removingArtifacts(threshold: 30).makeContainer()
        try #require(reduced._checkConsistency())
        
        #expect(reduced.tracks[0].notes.count == 2)
        #expect(reduced.tracks[0].notes == [MIDINote(onset: 0, offset: 1, note: 50, velocity: 20), MIDINote(onset: 1.01, offset: 1.5, note: 50, velocity: 50)])
    }
    
    @Test func consistencyChecks() async throws {
        let container = try MIDIContainer(at: "/Users/vaida/DataBase/Swift Package/Test Reference/MIDIKit/Sad Machine.mid")
        try #require(container._checkConsistency())
        let indexed = container.indexed()
        #expect(await indexed.removingArtifacts(threshold: 40).makeContainer()._checkConsistency())
    }
    
    @Test(.disabled("Does nothing")) func tests() async throws {
        let container = try MIDIContainer(at: "/Users/vaida/DataBase/Swift Package/Test Reference/MIDIKit/The Gardens.mid")
        try #require(container._checkConsistency())
        let indexed = container.indexed()
        let processed = await indexed.removingArtifacts(threshold: 40).makeContainer()
        #expect(processed._checkConsistency())
    }
}
