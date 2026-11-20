//
//  WriteTimingTests.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import Testing
import Foundation
import AudioToolbox
@testable
import MIDIKit


// MARK: - Support

/// A deterministic generator, so random cases are reproducible.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

private func roundTrip(_ container: MIDIContainer) throws -> MIDIContainer {
    try MIDIContainer(data: container.data())
}

/// The precision of a time read back from a file, which Core Audio reports with the precision of a `Float32`.
private func readPrecision(at time: Double) -> Double {
    Double(Float(time).ulp)
}


// MARK: - Tests

@Suite(.timeLimit(.minutes(1)))
struct WriteTimingTests {

    @Test
    func resolution() throws {
        #expect(MIDIContainer.writeResolution == 9600)

        let data = try MIDIContainer(tracks: [MIDITrack(notes: [MIDINote(onset: 0, offset: 1, pitch: 60, velocity: 100)])]).data()
        #expect(UInt16(data[12]) << 8 | UInt16(data[13]) == 9600)
    }

    /// Times on a grid that divides 9,600 come back where they were, however long the file: none of the gaps are rounded.
    @Test(arguments: [96, 384, 480, 960, 4800])
    func noDriftOnCommonGrids(ticksPerBeat: Int) throws {
        let step = 1 / Double(ticksPerBeat)
        let notes = (0..<4000).map { index in
            MIDINote(onset: Double(index) * step, offset: Double(index) * step + step / 2, pitch: UInt8(40 + index % 40), velocity: 100)
        }
        let read = try roundTrip(MIDIContainer(tracks: [MIDITrack(notes: notes)])).tracks[0].notes.contents.sorted()

        #expect(read.count == notes.count)
        for (original, read) in zip(notes.sorted(), read) {
            #expect(abs(read.onset - original.onset) <= readPrecision(at: original.onset))
        }
    }

    /// Times off the grid move by at most half a tick, and the error does not grow along the file.
    @Test
    func arbitraryTimesStayWithinHalfATick() throws {
        var generator = SplitMix64(state: 3)
        let notes = (0..<5000).map { _ in
            let onset = Double.random(in: 0..<2000, using: &generator)
            return MIDINote(onset: onset, offset: onset + Double.random(in: 0.01..<2, using: &generator), pitch: UInt8.random(in: 21...108, using: &generator), velocity: 100)
        }
        let read = try roundTrip(MIDIContainer(tracks: [MIDITrack(notes: notes)])).tracks[0].notes.contents.sorted()

        #expect(read.count == notes.count)
        let halfTick = 0.5 / Double(MIDIContainer.writeResolution)
        for (original, read) in zip(notes.sorted(), read) {
            #expect(abs(read.onset - original.onset) <= halfTick + readPrecision(at: original.onset))
        }
    }

    /// A note or sustain shorter than a tick is written one tick long, rather than with no length and lost.
    @Test
    func shortNotesLastATick() throws {
        let tick = 1 / Double(MIDIContainer.writeResolution)
        let container = MIDIContainer(tracks: [MIDITrack(
            notes: [MIDINote(onset: 1, offset: 1 + 1e-6, pitch: 60, velocity: 100), MIDINote(onset: 2, offset: 3, pitch: 62, velocity: 100)],
            sustains: [MIDISustainEvent(onset: 4, offset: 4 + 1e-6)]
        )])
        let track = try roundTrip(container).tracks[0]

        #expect(track.notes.count == 2)
        let short = try #require(track.notes.first { $0.pitch == 60 })
        #expect(abs(short.offset - short.onset - tick) < 1e-9)
        #expect(track.sustains.count == 1)
        #expect(abs(track.sustains[0].offset - track.sustains[0].onset - tick) < 1e-9)
    }

    /// A note that ends where the next note on its key starts keeps both notes, even when its duration does not fit a `Float32` exactly. Found in an ASAP file: rounding the duration up made the note end after the next one started, and a note was lost.
    @Test
    func touchingNotesOnOneKeySurvive() throws {
        let tick = 1 / Double(MIDIContainer.writeResolution)
        let notes = [
            MIDINote(onset: 3_259_240 * tick, offset: 3_260_820 * tick, pitch: 57, velocity: 3),
            MIDINote(onset: 3_260_820 * tick, offset: 3_262_040 * tick, pitch: 57, velocity: 40),
        ]
        let read = try roundTrip(MIDIContainer(tracks: [MIDITrack(notes: notes)])).tracks[0].notes.contents.sorted()
        
        #expect(read.map(\.velocity) == [3, 40])
    }
    
    /// A note longer than 512 beats, where a `Float32` step exceeds half a tick, keeps its length to the tick, and a later note stays on its tick.
    @Test
    func longNotesKeepTheirTicks() throws {
        let tick = 1 / Double(MIDIContainer.writeResolution)
        let notes = [
            MIDINote(onset: 0, offset: 4_959_839 * tick, pitch: 60, velocity: 80),
            MIDINote(onset: 4_960_000 * tick, offset: 4_960_100 * tick, pitch: 62, velocity: 80),
        ]
        let read = try roundTrip(MIDIContainer(tracks: [MIDITrack(notes: notes)])).tracks[0].notes.contents.sorted()
        
        #expect(read.map { ($0.offset / tick).rounded() } == [4_959_839, 4_960_100])
        #expect(read.map { ($0.onset / tick).rounded() } == [0, 4_960_000])
    }
    
    /// The sequence for playback keeps exact times; only files are written on the grid.
    @Test
    func sequenceKeepsExactTimes() throws {
        let onset = 1.0 / 7
        let sequence = try MIDIContainer(tracks: [MIDITrack(notes: [MIDINote(onset: onset, offset: 1, pitch: 60, velocity: 100)])]).makeSequence()
        defer { DisposeMusicSequence(sequence) }

        var track: MusicTrack?
        MusicSequenceGetIndTrack(sequence, 0, &track)
        var iterator: MusicEventIterator?
        NewMusicEventIterator(track!, &iterator)
        defer { DisposeMusicEventIterator(iterator!) }
        var timestamp: MusicTimeStamp = 0
        var type: MusicEventType = 0
        var data: UnsafeRawPointer?
        var size: UInt32 = 0
        MusicEventIteratorGetEventInfo(iterator!, &timestamp, &type, &data, &size)

        #expect(type == kMusicEventType_MIDINoteMessage)
        #expect(timestamp == onset)
    }

    // MARK: Raw data

    @Test
    func rawDataRoundTrips() throws {
        let messages: [MIDIKit.MIDIRawData] = [
            MIDIKit.MIDIRawData(timestamp: 0.5, data: Data([0xF0, 0x7E, 0x7F, 0x09, 0x01, 0xF7])), // GM System On
            MIDIKit.MIDIRawData(timestamp: 1, data: Data([0xF0, 0x43, 0x10, 0x4C, 0x00, 0x00, 0x7E, 0x00, 0xF7])),
            MIDIKit.MIDIRawData(timestamp: 2, data: Data([0xF0] + (0..<298).map { UInt8($0 % 128) } + [0xF7])), // 300 bytes
        ]
        var track = MIDITrack(notes: [MIDINote(onset: 0, offset: 4, pitch: 60, velocity: 100)])
        track.rawData = messages
        let read = try roundTrip(MIDIContainer(tracks: [track])).tracks[0].rawData

        #expect(read == messages)
    }

    @Test
    func pointerHoldsTheWholeMessage() {
        let raw = MIDIKit.MIDIRawData(timestamp: 0, data: Data([0xF0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0xF7]))
        raw.withUnsafePointer { pointer in
            #expect(pointer.pointee.length == 11)
            let bytes = UnsafeRawPointer(pointer) + 4
            #expect(Data(bytes: bytes, count: 11) == raw.data)
        }

        let empty = MIDIKit.MIDIRawData(timestamp: 0, data: Data())
        empty.withUnsafePointer { #expect($0.pointee.length == 0) }
    }

    // MARK: Meta events

    @Test
    func metaEventsRoundTrip() throws {
        let text = MIDIMetaEvent(timestamp: 1, type: 0x01, data: Data(String(repeating: "MIDIKit ", count: 125).utf8)) // 1,000 bytes
        let key = MIDIMetaEvent(timestamp: 0, type: 0x59, data: Data([0xFD, 0]))
        var track = MIDITrack(notes: [MIDINote(onset: 0, offset: 4, pitch: 60, velocity: 100)])
        track.metaEvents = [key, text]
        var container = MIDIContainer(tracks: [track])
        container.tempo.timeSignature = MIDITimeSignature(3, 4)

        let read = try roundTrip(container)
        #expect(read.tracks[0].metaEvents.contains(text))
        #expect(read.tracks[0].metaEvents.contains(key))
        #expect(read.tempo.timeSignature == MIDITimeSignature(3, 4))
    }

}
