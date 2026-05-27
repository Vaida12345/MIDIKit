//
//  ContainerAndTempoTests.swift
//  MIDIKit
//

@testable
import MIDIKit
import Testing
import AudioToolbox


@Suite("MIDIContainer")
struct MIDIContainerTests {

    @Test func initEmpty() {
        let container = MIDIContainer()
        #expect(container.tracks.isEmpty)
    }

    @Test func initWithTracks() {
        let track = MIDITrack(notes: [MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)])
        let container = MIDIContainer(tracks: [track])
        #expect(container.tracks.count == 1)
        #expect(container.tracks[0].notes.count == 1)
    }

    @Test func initWithNotes() {
        let notes = MIDINotes([MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)])
        let container = MIDIContainer(notes: notes)
        #expect(container.tracks.count == 1)
        #expect(container.tracks[0].notes.count == 1)
    }

    @Test func initWithNotesAndSustains() {
        let notes = MIDINotes([MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)])
        let sustains = MIDISustainEvents([MIDISustainEvent(onset: 0, offset: 1)])
        let container = MIDIContainer(notes: notes, sustains: sustains)
        #expect(container.tracks[0].sustains.count == 1)
    }

    @Test func initWithCustomTempo() {
        let tempo = MIDITempoTrack(tempos: [MIDITempoTrack.Tempo(timestamp: 0, tempo: 100)])
        let container = MIDIContainer(tracks: [], tempo: tempo)
        #expect(container.tempo.contents[0].tempo == 100)
    }

    @Test func equatable() {
        let a = MIDIContainer(tracks: [
            MIDITrack(notes: [MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)])
        ])
        let b = MIDIContainer(tracks: [
            MIDITrack(notes: [MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)])
        ])
        #expect(a == b)
    }

    @Test func notEqualDifferentTracks() {
        let a = MIDIContainer(tracks: [
            MIDITrack(notes: [MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)])
        ])
        let b = MIDIContainer(tracks: [])
        #expect(a != b)
    }

}


@Suite("MIDIContainer.Indexed")
struct MIDIContainerIndexedTests {

    @Test func indexedRoundtrip() {
        let original = MIDIContainer(notes: MIDINotes([
            MIDINote(onset: 0, offset: 1, note: 60, velocity: 100),
            MIDINote(onset: 2, offset: 3, note: 64, velocity: 80),
        ]))
        let indexed = original.indexed()
        let roundtripped = indexed.makeContainer()
        #expect(roundtripped.tracks.count == 1)
        #expect(roundtripped.tracks[0].notes.count == 2)
    }

    @Test func indexedEmpty() {
        let container = MIDIContainer()
        let indexed = container.indexed()
        #expect(indexed.isEmpty)
        let result = indexed.makeContainer()
        #expect(result.tracks.count == 1)
        #expect(result.tracks[0].notes.isEmpty)
    }

    @Test func indexedMultipleTracks() {
        let track1 = MIDITrack(notes: [MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)])
        let track2 = MIDITrack(notes: [MIDINote(onset: 2, offset: 3, note: 64, velocity: 80)])
        let container = MIDIContainer(tracks: [track1, track2])
        let indexed = container.indexed()
        let result = indexed.makeContainer()
        // Multi-track indexed combines into a single track with channel encoding
        #expect(result.tracks.count == 1)
        #expect(result.tracks[0].notes.count == 2)
    }

}


@Suite("MIDITempoTrack")
struct MIDITempoTrackTests {

    @Test func initDefault() {
        let tempo = MIDITempoTrack()
        #expect(tempo.events.isEmpty)
        #expect(tempo.contents.isEmpty)
    }

    @Test func initWithTempos() {
        let tempo = MIDITempoTrack(tempos: [
            MIDITempoTrack.Tempo(timestamp: 0, tempo: 120),
            MIDITempoTrack.Tempo(timestamp: 10, tempo: 140),
        ])
        #expect(tempo.contents.count == 2)
        #expect(tempo.contents[0].tempo == 120)
        #expect(tempo.contents[1].tempo == 140)
    }

    @Test func setTimeSignatureDefault() {
        var tempo = MIDITempoTrack()
        tempo.setTimeSignature(beatsPerMeasure: 3, beatsPerNote: 4)
        #expect(tempo.events.count == 1)
        let event = tempo.events[0]
        #expect(event.type == 0x58) // time signature meta event type
        #expect(event.data[0] == 3) // numerator
        #expect(event.data[1] == 2) // log2(4) = 2
    }

    @Test func setTimeSignatureUpdatesExisting() {
        var tempo = MIDITempoTrack()
        tempo.setTimeSignature(beatsPerMeasure: 4, beatsPerNote: 4)
        tempo.setTimeSignature(beatsPerMeasure: 6, beatsPerNote: 8)
        #expect(tempo.events.count == 1) // should update, not append
        #expect(tempo.events[0].data[0] == 6) // numerator
        #expect(tempo.events[0].data[1] == 3) // log2(8) = 3
    }

    @Test func tempoDefaultIs120() {
        let tempo = MIDITempoTrack.Tempo.default
        #expect(tempo.timestamp == 0)
        #expect(tempo.tempo == 120)
    }

    @Test func tempoInit() {
        let tempo = MIDITempoTrack.Tempo(timestamp: 5.0, tempo: 80.0)
        #expect(tempo.timestamp == 5.0)
        #expect(tempo.tempo == 80.0)
    }

    @Test func arrayLiteralInit() {
        let tempo: MIDITempoTrack = [
            MIDITempoTrack.Tempo(timestamp: 0, tempo: 100),
            MIDITempoTrack.Tempo(timestamp: 4, tempo: 120),
        ]
        #expect(tempo.contents.count == 2)
    }

}


@Suite("MIDIMetaEvent")
struct MIDIMetaEventTests {

    @Test func initBasic() {
        let event = MIDIMetaEvent(timestamp: 1.0, type: 0x51, data: Data([0x07, 0xA1, 0x20]))
        #expect(event.timestamp == 1.0)
        #expect(event.type == 0x51)
        #expect(event.data == Data([0x07, 0xA1, 0x20]))
    }

    @Test func defaultTimeSignature() {
        let event = MIDIMetaEvent.defaultTimeSignature
        #expect(event.timestamp == 0.0)
        #expect(event.type == 0x58) // time signature
        #expect(event.data == Data([4, 2, 24, 8])) // 4/4, 24 MIDI clocks, 8 32nd notes
    }

    @Test func equatable() {
        let a = MIDIMetaEvent(timestamp: 0, type: 1, data: Data([1, 2, 3]))
        let b = MIDIMetaEvent(timestamp: 0, type: 1, data: Data([1, 2, 3]))
        #expect(a == b)
    }

}


@Suite("MIDIRawData")
struct MIDIRawDataTests {

    @Test func initAndAccess() {
        let rawData = MIDIRawData(data: Data([0x01, 0x02, 0x03]))
        #expect(rawData.data == Data([0x01, 0x02, 0x03]))
    }

    @Test func equatable() {
        let a = MIDIRawData(data: Data([1, 2, 3]))
        let b = MIDIRawData(data: Data([1, 2, 3]))
        #expect(a == b)
    }

    @Test func notEqual() {
        let a = MIDIRawData(data: Data([1, 2, 3]))
        let b = MIDIRawData(data: Data([4, 5, 6]))
        #expect(a != b)
    }

}


@Suite("MIDIMetaEvent.withUnsafePointer")
struct MetaEventAudioToolboxTests {

    @Test func roundtripViaAudioToolbox() {
        let original = MIDIMetaEvent(timestamp: 1.0, type: 0x01, data: Data([0x41, 0x42, 0x43]))
        let toolboxValue: AudioToolbox.MIDIMetaEvent = original.withUnsafePointer { pointer in
            return pointer.pointee
        }
        #expect(toolboxValue.metaEventType == 0x01)
        #expect(toolboxValue.dataLength == 3)
    }

}


@Suite("MIDIRawData.withUnsafePointer")
struct RawDataAudioToolboxTests {

    @Test func roundtripViaAudioToolbox() {
        let original = MIDIRawData(data: Data([0x10, 0x20, 0x30]))
        let toolboxValue: AudioToolbox.MIDIRawData = original.withUnsafePointer { pointer in
            return pointer.pointee
        }
        #expect(toolboxValue.length == 3)
    }

}
