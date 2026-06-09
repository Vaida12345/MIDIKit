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
    
    private struct DeterministicRandomNumberGenerator: RandomNumberGenerator {
        private var state: UInt64
        
        /// Creates a reproducible random-number generator with the supplied seed.
        init(seed: UInt64) {
            self.state = seed
        }
        
        /// Advances the generator and returns the next pseudorandom value.
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }
    
    @Test func readEmptyData() async throws {
        let data = try FinderItem(at: "/Users/vaida/DataBase/Swift Package/Test Reference/MIDIKit/empty.mid").load(.data)
        let container = try MIDIContainer(data: data)
        #expect(container.tracks == [])
    }
    
    /// Verifies that valid notes survive a Standard MIDI File round trip within the accepted beat precision.
    @Test func consistency() async throws {
        var generator = DeterministicRandomNumberGenerator(seed: 0x4D49_4449_4B69_74)
        var track = MIDITrack()
        while track.notes.count < 1000 {
            let onset = Double.random(in: 0...100, using: &generator)
            let duration = Double.random(in: 0...10, using: &generator) + 1/128 // never zero
            let pitch = UInt8.random(in: 21...108, using: &generator)
            let velocity = UInt8.random(in: 1...127, using: &generator)
            let note = MIDINote(onset: onset, offset: onset + duration, note: pitch, velocity: velocity)
            let indexed = MIDIContainer(tracks: [track]).indexed()
            try withExtendedLifetime(indexed) { indexed in
                guard indexed.notes[pitch].isNil(or: { !$0.overlaps(with: note) }) else { return }
                
                track.notes.append(note)
                try #require(MIDIContainer(tracks: [track])._checkConsistency())
            }
        }
        try #require(MIDIContainer(tracks: [track])._checkConsistency())
        
        let dest = FinderItem.temporaryDirectory/"\(UUID()).mid"
        defer { try? dest.remove() }
        try MIDIContainer(tracks: [track]).write(to: dest)
        let read = try MIDIContainer(at: dest)
        
        try #require(read.tracks.count == 1)
        #expect(read.tempo.events == [.defaultTimeSignature])
        #expect(read.tempo.contents == [.default])
        
        let writtenNotes = track.notes.contents
        let readNotes = read.tracks[0].notes.contents
        try #require(readNotes.count == writtenNotes.count, "\(read.tracks[0]), \(track.notes)")
        
        // CoreAudio may accumulate sub-tick rounding while encoding ordered delta times.
        let tolerance: CGFloat = 1/128 / 2
        
        /// Orders notes by losslessly serialized identity, then by onset within matching identities.
        func ordered(_ notes: [MIDINote]) -> [MIDINote] {
            notes.sorted { lhs, rhs in
                if lhs.note != rhs.note { return lhs.note < rhs.note }
                if lhs.velocity != rhs.velocity { return lhs.velocity < rhs.velocity }
                if lhs.channel != rhs.channel { return lhs.channel < rhs.channel }
                if lhs.releaseVelocity != rhs.releaseVelocity { return lhs.releaseVelocity < rhs.releaseVelocity }
                return lhs.onset < rhs.onset
            }
        }
        
        for (lhs, rhs) in zip(ordered(writtenNotes), ordered(readNotes)) {
            #expect(abs(lhs.onset - rhs.onset) < tolerance, "\(lhs), \(rhs)")
            try #require(rhs.duration > 0)
            #expect(abs(lhs.duration - rhs.duration) < tolerance, "\(lhs), \(rhs)")
            #expect(abs(lhs.offset - rhs.offset) < tolerance, "\(lhs), \(rhs)")
            #expect(lhs.note == rhs.note)
            #expect(lhs.velocity == rhs.velocity)
            #expect(lhs.channel == rhs.channel)
            #expect(lhs.releaseVelocity == rhs.releaseVelocity)
        }
    }
    
}
