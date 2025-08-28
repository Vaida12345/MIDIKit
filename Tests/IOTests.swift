//
//  IOTests.swift
//  MIDIKit
//
//  Created by Vaida on 2025-05-31.
//

import Foundation
import Testing
import MIDIKit
import FinderItem


@Suite
struct IOTests {
    
    @Test func readEmptyData() async throws {
        let data = try FinderItem(at: "/Users/vaida/DataBase/Swift Package/Test Reference/MIDIKit/empty.mid").load(.data)
        let container = try MIDIContainer(data: data)
        #expect(container.tracks == [])
    }
    
    @Test func consistency() async throws {
        var track = MIDITrack()
        while track.notes.count < 100 {
            let onset = Double.random(in: 0...100)
            let duration = Double.random(in: 0...10) + 1/128 // never zero
            let pitch = UInt8.random(in: 21...108)
            let note = MIDINote(onset: onset, offset: onset + duration, note: pitch, velocity: .random(in: 1...127))
            guard MIDIContainer(tracks: [track]).indexed().notes[pitch].isNil(or: { !$0.overlaps(with: note) }) else { continue }
            
            track.notes.append(note)
        }
        
        let dest = try FinderItem.temporaryDirectory(intent: .general)/"\(UUID()).mid"
        defer { try? dest.remove() }
        try MIDIContainer(tracks: [track]).write(to: dest)
        let read = try MIDIContainer(at: dest)
        
        try #require(read.tracks.count == 1)
        #expect(read.tempo.events == [.defaultTimeSignature])
        #expect(read.tempo.contents == [.default])
        
        track.notes.sort()
        
        try #require(read.tracks[0].notes.count == track.notes.count, "\(read.tracks[0]), \(track.notes)")
        try #require(read.tracks[0].notes.map(\.note) == track.notes.map(\.note), "\(read.tracks[0]), \(track.notes)")
        
        for (lhs, rhs) in zip(track.notes, read.tracks[0].notes) {
            #expect(abs(lhs.onset - rhs.onset) < 1/128)
            try #require(rhs.duration > 0)
            #expect(abs(lhs.duration - rhs.duration) < 1/128, "\(lhs), \(rhs)")
            #expect(abs(lhs.offset - rhs.offset) < 1/128, "\(lhs), \(rhs)")
            #expect(lhs.note == rhs.note)
            #expect(lhs.velocity == rhs.velocity)
            #expect(lhs.channel == rhs.channel)
            #expect(lhs.releaseVelocity == rhs.releaseVelocity)
        }
    }
    
}
