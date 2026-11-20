//
//  TimeSignatureTests.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import Testing
import Foundation
import MIDIKit


@Suite(.timeLimit(.minutes(1)))
struct TimeSignatureTests {

    @Test
    func readingAMetaEvent() throws {
        let threeFour = try #require(MIDITimeSignature(MIDIMetaEvent(timestamp: 0, type: 0x58, data: Data([3, 2, 24, 8]))))
        #expect(threeFour.numerator == 3 && threeFour.denominator == 4)
        #expect(threeFour.clocksPerClick == 24 && threeFour.thirtySecondNotesPerQuarter == 8)

        let sixEight = try #require(MIDITimeSignature(MIDIMetaEvent(timestamp: 0, type: 0x58, data: Data([6, 3, 36, 8]))))
        #expect(sixEight == MIDITimeSignature(6, 8, clocksPerClick: 36))

        #expect(MIDITimeSignature(MIDIMetaEvent(timestamp: 0, type: 0x59, data: Data([3, 2, 24, 8]))) == nil) // a key signature
        #expect(MIDITimeSignature(MIDIMetaEvent(timestamp: 0, type: 0x58, data: Data([3, 2, 24]))) == nil) // too short
        #expect(MIDITimeSignature(MIDIMetaEvent(timestamp: 0, type: 0x58, data: Data([0, 2, 24, 8]))) == nil) // no beats
        #expect(MIDITimeSignature(MIDIMetaEvent(timestamp: 0, type: 0x58, data: Data([3, 8, 24, 8]))) == nil) // 1/256
    }

    @Test(arguments: [(2, 2), (3, 4), (4, 4), (5, 8), (7, 16), (12, 8), (1, 1), (255, 128)])
    func eventRoundTrips(numerator: Int, denominator: Int) {
        let signature = MIDITimeSignature(numerator, denominator)
        let event = signature.event(at: 4)
        #expect(event.timestamp == 4 && event.type == 0x58)
        #expect(MIDITimeSignature(event) == signature)
    }

    @Test
    func defaultIsFourFour() {
        #expect(MIDITimeSignature.default == MIDITimeSignature(4, 4))
        #expect(MIDITimeSignature.default.event() == MIDIMetaEvent.defaultTimeSignature)
        #expect(MIDIMetaEvent.defaultTimeSignature.data == Data([4, 2, 24, 8]))
        #expect(MIDITimeSignature.default.description == "4/4")
    }

    @Test
    func tempoTrackTimeSignature() {
        var tempo = MIDITempoTrack()
        #expect(tempo.timeSignature == nil)

        tempo.timeSignature = MIDITimeSignature(3, 4)
        #expect(tempo.timeSignature == MIDITimeSignature(3, 4))
        #expect(tempo.metaEvents.count == 1 && tempo.metaEvents[0].timestamp == 0)

        // Setting again replaces the event instead of adding one.
        tempo.timeSignature = MIDITimeSignature(6, 8)
        #expect(tempo.timeSignature == MIDITimeSignature(6, 8))
        #expect(tempo.metaEvents.count == 1)

        tempo.timeSignature = nil
        #expect(tempo.timeSignature == nil)
        #expect(tempo.metaEvents.isEmpty)
    }

    @Test
    func survivesAFile() throws {
        var container = MIDIContainer(tracks: [MIDITrack(notes: [MIDINote(onset: 0, offset: 1, pitch: 60, velocity: 100)])])
        container.tempo.timeSignature = MIDITimeSignature(3, 4)

        let read = try MIDIContainer(data: container.data())
        #expect(read.tempo.timeSignature == MIDITimeSignature(3, 4))
    }

    /// A file written without a time signature reads back as 4/4, as before.
    @Test
    func aFileWithoutOneGetsTheDefault() throws {
        let container = MIDIContainer(tracks: [MIDITrack(notes: [MIDINote(onset: 0, offset: 1, pitch: 60, velocity: 100)])])

        let read = try MIDIContainer(data: container.data())
        #expect(read.tempo.timeSignature == .default)
    }

    @Test
    func coding() throws {
        let signature = MIDITimeSignature(7, 8, clocksPerClick: 12)
        let decoded = try JSONDecoder().decode(MIDITimeSignature.self, from: JSONEncoder().encode(signature))
        #expect(decoded == signature)

        let invalid = Data(#"{"numerator":3,"denominator":6,"clocksPerClick":24,"thirtySecondNotesPerQuarter":8}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(MIDITimeSignature.self, from: invalid) }
    }

}
