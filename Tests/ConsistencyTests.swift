//
//  ConsistencyTests.swift
//  MIDIKit
//
//  Created by Vaida on 2025-08-29.
//

import Testing
import MIDIKit


@Suite
struct ConsistencyTests {
    
    @Test
    func checkPitch() {
        do {
            let notes = [
                MIDINote(onset: 10, offset: 11, note: 20, velocity: 10)
            ]
            let container = MIDIContainer(tracks: [MIDITrack(notes: notes)])
            #expect(!container._checkConsistency())
        }
        do {
            let notes = [
                MIDINote(onset: 10, offset: 11, note: 110, velocity: 10)
            ]
            let container = MIDIContainer(tracks: [MIDITrack(notes: notes)])
            #expect(!container._checkConsistency())
        }
        do {
            let notes = [
                MIDINote(onset: 10, offset: 11, note: 50, velocity: 10)
            ]
            let container = MIDIContainer(tracks: [MIDITrack(notes: notes)])
            #expect(container._checkConsistency())
        }
    }
    
    @Test
    func checkVelocity() {
        do {
            let notes = [
                MIDINote(onset: 10, offset: 11, note: 50, velocity: 0)
            ]
            let container = MIDIContainer(tracks: [MIDITrack(notes: notes)])
            #expect(!container._checkConsistency())
        }
    }
    
    @Test
    func checkSustains() {
        do {
            let sustains: [MIDITrack.SustainEvent] = [
                MIDISustainEvent(onset: 0, offset: 10),
                MIDISustainEvent(onset: 5, offset: 15),
            ]
            let container = MIDIContainer(tracks: [MIDITrack(sustains: sustains)])
            #expect(!container._checkConsistency())
        }
        
        do {
            let sustains: [MIDITrack.SustainEvent] = [
                MIDISustainEvent(onset: 0, offset: 4.9),
                MIDISustainEvent(onset: 5, offset: 15),
            ]
            let container = MIDIContainer(tracks: [MIDITrack(sustains: sustains)])
            #expect(container._checkConsistency())
        }
    }
    
    @Test
    func checkOverlaps() {
        do {
            let notes = [
                MIDINote(onset: 0, offset: 10, note: 50, velocity: 50),
                MIDINote(onset: 5, offset: 15, note: 50, velocity: 50),
            ]
            let container = MIDIContainer(tracks: [MIDITrack(notes: notes)])
            #expect(!container._checkConsistency())
        }
        
        do {
            let notes = [
                MIDINote(onset: 0, offset: 4.9, note: 50, velocity: 50),
                MIDINote(onset: 5, offset: 15, note: 50, velocity: 50),
            ]
            let container = MIDIContainer(tracks: [MIDITrack(notes: notes)])
            #expect(container._checkConsistency())
        }
    }
    
}
