//
//  ChannelEventTests.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import Testing
import AudioToolbox
@testable
import MIDIKit


@Suite(.timeLimit(.minutes(1)))
struct ChannelEventTests {

    /// One event of every message type, on channels 0 and 9, at increasing onsets.
    private static let events: [MIDIChannelEvent] = {
        let messages: [MIDIChannelEvent.Message] = [
            .controlChange(controller: 1, value: 90),
            .controlChange(controller: 67, value: 127), // soft pedal
            .controlChange(controller: 123, value: 0), // all notes off, a channel mode message
            .programChange(program: 42),
            .channelPressure(pressure: 77),
            .polyphonicKeyPressure(key: 60, pressure: 33),
            .pitchBend(value: 0),
            .pitchBend(value: 0x2000),
            .pitchBend(value: 0x3FFF),
            .pitchBend(value: 0x1234),
        ]
        var events: [MIDIChannelEvent] = []
        for message in messages {
            for channel: UInt8 in [0, 9] {
                events.append(MIDIChannelEvent(onset: Double(events.count + 1) / 2, channel: channel, message: message))
            }
        }
        return events
    }()

    @Test
    func roundTripsThroughAFile() throws {
        let track = MIDITrack(
            notes: [MIDINote(onset: 0, offset: 20, pitch: 60, velocity: 100)],
            sustains: [MIDISustainEvent(onset: 1, offset: 2)],
            channelEvents: MIDIChannelEvents(Self.events)
        )
        let read = try MIDIContainer(data: MIDIContainer(tracks: [track]).data())

        #expect(read.tracks.count == 1)
        #expect(read.tracks[0].channelEvents.contents == Self.events)
        #expect(read.tracks[0].sustains.contents == [MIDISustainEvent(onset: 1, offset: 2)])
    }

    @Test
    func readsChannelMessages() throws {
        func event(_ status: UInt8, _ data1: UInt8, _ data2: UInt8) -> MIDIChannelEvent? {
            MIDIChannelEvent(onset: 3, MIDIChannelMessage(status: status, data1: data1, data2: data2, reserved: 0))
        }

        #expect(event(0xB3, 7, 100) == MIDIChannelEvent(onset: 3, channel: 3, message: .controlChange(controller: 7, value: 100)))
        #expect(event(0xC0, 5, 0) == MIDIChannelEvent(onset: 3, message: .programChange(program: 5)))
        #expect(event(0xDF, 64, 0) == MIDIChannelEvent(onset: 3, channel: 15, message: .channelPressure(pressure: 64)))
        #expect(event(0xA1, 60, 20) == MIDIChannelEvent(onset: 3, channel: 1, message: .polyphonicKeyPressure(key: 60, pressure: 20)))
        // Pitch bend sends the low 7 bits first.
        #expect(event(0xE2, 0x00, 0x40) == MIDIChannelEvent(onset: 3, channel: 2, message: .pitchBend(value: 0x2000)))
        #expect(event(0xE0, 0x7F, 0x7F) == MIDIChannelEvent(onset: 3, message: .pitchBend(value: 0x3FFF)))

        // Notes and system messages are not channel events.
        #expect(event(0x90, 60, 100) == nil)
        #expect(event(0x80, 60, 0) == nil)
        #expect(event(0xF8, 0, 0) == nil)
    }

    @Test
    func writesChannelMessages() {
        let pitchBend = MIDIChannelEvent(onset: 0, channel: 4, message: .pitchBend(value: 0x1234)).channelMessage
        #expect(pitchBend.status == 0xE4 && pitchBend.data1 == 0x34 && pitchBend.data2 == 0x24)

        let program = MIDIChannelEvent(onset: 0, channel: 9, message: .programChange(program: 42)).channelMessage
        #expect(program.status == 0xC9 && program.data1 == 42 && program.data2 == 0)
    }

    /// At the same time, a SysEx message and a program change are written before the note they set up.
    @Test
    func setupIsWrittenBeforeNotesAtTheSameTime() throws {
        var track = MIDITrack(
            notes: [MIDINote(onset: 0, offset: 1, pitch: 60, velocity: 80)],
            channelEvents: MIDIChannelEvents([MIDIChannelEvent(onset: 0, message: .programChange(program: 40))])
        )
        track.rawData = [MIDIRawData(timestamp: 0, data: Data([0xF0, 0x7E, 0x7F, 0x09, 0x01, 0xF7]))]
        let bytes = Array(try MIDIContainer(tracks: [track]).data())

        func position(of pattern: [UInt8]) throws -> Int {
            try #require((0...(bytes.count - pattern.count)).first { bytes[$0..<($0 + pattern.count)].elementsEqual(pattern) })
        }
        let noteOn = try position(of: [0x90, 60])
        #expect(try position(of: [0xC0, 40]) < noteOn)
        #expect(try position(of: [0x7E, 0x7F, 0x09, 0x01, 0xF7]) < noteOn)
    }

    /// The sustain pedal is read as sustains, on any channel, and never as a channel event.
    @Test
    func sustainPedalIsNotAChannelEvent() throws {
        let sequence = try Self.sequence { track in
            Self.addNote(to: track, at: 0, duration: 8)
            Self.addControlChange(to: track, at: 1, channel: 2, controller: 64, value: 100)
            Self.addControlChange(to: track, at: 3, channel: 2, controller: 64, value: 0)
            Self.addControlChange(to: track, at: 4, channel: 0, controller: 67, value: 127)
        }
        defer { DisposeMusicSequence(sequence) }
        let container = try MIDIContainer(sequence: sequence)

        #expect(container.tracks[0].sustains.contents == [MIDISustainEvent(onset: 1, offset: 3)])
        #expect(container.tracks[0].channelEvents.contents == [MIDIChannelEvent(onset: 4, message: .controlChange(controller: 67, value: 127))])
    }

    /// A pedal still down at the end of a track is released at the end of the track.
    @Test
    func sustainOpenAtTheEndOfATrack() throws {
        let sequence = try Self.sequence { track in
            Self.addNote(to: track, at: 0, duration: 6)
            Self.addControlChange(to: track, at: 1, channel: 0, controller: 64, value: 127)
            Self.addControlChange(to: track, at: 2, channel: 0, controller: 64, value: 0)
            Self.addControlChange(to: track, at: 4, channel: 0, controller: 64, value: 127)
        }
        defer { DisposeMusicSequence(sequence) }
        let container = try MIDIContainer(sequence: sequence)

        #expect(container.tracks[0].sustains.contents == [MIDISustainEvent(onset: 1, offset: 2), MIDISustainEvent(onset: 4, offset: 6)])
    }

    /// A pedal lifted and pressed again on the same tick is a pedal change: it loads as two sustains, 1/128 beat apart, and is written back as two.
    @Test
    func samePedalChangeLoadsAsTwoSustains() throws {
        let sequence = try Self.sequence { track in
            Self.addNote(to: track, at: 0, duration: 4)
            Self.addControlChange(to: track, at: 1, channel: 0, controller: 64, value: 127)
            Self.addControlChange(to: track, at: 2, channel: 0, controller: 64, value: 0)
            Self.addControlChange(to: track, at: 2, channel: 0, controller: 64, value: 127)
            Self.addControlChange(to: track, at: 3, channel: 0, controller: 64, value: 0)
        }
        defer { DisposeMusicSequence(sequence) }
        let container = try MIDIContainer(sequence: sequence)

        let expected = [MIDISustainEvent(onset: 1, offset: 2 - 1.0 / 128), MIDISustainEvent(onset: 2, offset: 3)]
        #expect(container.tracks[0].sustains.contents == expected)
        // 2 - 1/128 is a whole number of ticks at the write resolution.
        #expect(try MIDIContainer(data: container.data()).tracks[0].sustains.contents == expected)
    }


    // MARK: - Support

    private static func sequence(_ body: (MusicTrack) -> Void) throws -> MusicSequence {
        var sequence: MusicSequence?
        try #require(NewMusicSequence(&sequence) == noErr)
        var track: MusicTrack?
        try #require(MusicSequenceNewTrack(sequence!, &track) == noErr)
        body(track!)
        return sequence!
    }

    private static func addNote(to track: MusicTrack, at onset: MusicTimeStamp, duration: Float32) {
        var message = MIDINoteMessage(channel: 0, note: 60, velocity: 100, releaseVelocity: 0, duration: duration)
        MusicTrackNewMIDINoteEvent(track, onset, &message)
    }

    private static func addControlChange(to track: MusicTrack, at onset: MusicTimeStamp, channel: UInt8, controller: UInt8, value: UInt8) {
        var message = MIDIChannelMessage(status: 0xB0 | channel, data1: controller, data2: value, reserved: 0)
        MusicTrackNewMIDIChannelEvent(track, onset, &message)
    }

}
