//
//  Support.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import MIDIKit
@testable
import IndexedTrack


let gap = 1.0 / 128

func note(_ onset: Double, _ offset: Double, _ pitch: UInt8, velocity: UInt8 = 80) -> MIDINote {
    MIDINote(onset: onset, offset: offset, note: pitch, velocity: velocity)
}

func track(_ notes: [MIDINote], sustains: [MIDISustainEvent] = []) -> IndexedTrack {
    IndexedTrack(MIDIContainer(tracks: [MIDITrack(notes: notes, sustains: sustains)]))
}


/// A small deterministic generator, so the figures never change.
struct IndexedTrackRNG {
    
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
func cleanInput(seed: UInt64, count: Int) -> [MIDINote] {
    var rng = IndexedTrackRNG(seed: seed)
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

extension IndexedTrackRNG: RandomNumberGenerator { }


func isOrdered(_ lhs: MIDINote, _ rhs: MIDINote) -> Bool {
    lhs.onset < rhs.onset || (lhs.onset == rhs.onset && lhs.pitch < rhs.pitch)
}
