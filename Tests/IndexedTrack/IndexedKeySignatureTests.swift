//
//  IndexedKeySignatureTests.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import Testing
import Foundation
import MIDIKit
@testable
import IndexedTrack


// MARK: - Support

/// A melody that walks the scale of `tonic` up and down, then ends with a tonic triad, one beat per note.
private func scaleTrack(tonic: Int, minor: Bool = false) -> IndexedTrack {
    let steps = minor ? [0, 2, 3, 5, 7, 8, 11, 12] : [0, 2, 4, 5, 7, 9, 11, 12] // harmonic minor
    let pitches = (steps + steps.reversed().dropFirst()).map { 60 + tonic + $0 }
    var notes = pitches.enumerated().map { index, pitch in
        note(Double(index), Double(index) + 0.9, UInt8(pitch))
    }
    let end = Double(pitches.count)
    for degree in [0, minor ? 3 : 4, 7] {
        notes.append(note(end, end + 2, UInt8(48 + tonic + degree)))
    }
    return track(notes)
}


/// A key-signature meta event with the given signed number of sharps, in major.
private func keySignatureEvent(_ sharps: Int8, at timestamp: Double) -> MIDIMetaEvent {
    MIDIMetaEvent(timestamp: timestamp, type: 0x59, data: Data([UInt8(bitPattern: sharps), 0]))
}


// MARK: - Tests

@Suite(.timeLimit(.minutes(1)))
struct IndexedKeySignatureTests {

    @Test(arguments: 0..<12)
    func majorScales(tonic: Int) {
        #expect(scaleTrack(tonic: tonic).keySignature == IndexedTrack.KeySignature(majorTonic: tonic))
    }

    /// A minor key gives the signature of its relative major.
    @Test(arguments: 0..<12)
    func minorScales(tonic: Int) {
        #expect(scaleTrack(tonic: tonic, minor: true).keySignature == IndexedTrack.KeySignature(majorTonic: tonic + 3))
    }

    @Test
    func knownKeys() {
        #expect(scaleTrack(tonic: 0).keySignature == .natural) // C major
        #expect(scaleTrack(tonic: 7).keySignature?.sharps == 1) // G major
        #expect(scaleTrack(tonic: 5).keySignature?.sharps == -1) // F major
        #expect(scaleTrack(tonic: 9, minor: true).keySignature == .natural) // A minor
        #expect(scaleTrack(tonic: 2, minor: true).keySignature?.sharps == -1) // D minor
        #expect(scaleTrack(tonic: 4, minor: true).keySignature?.sharps == 1) // E minor
    }

    /// Short chromatic notes count little next to the held notes of the key.
    @Test
    func shortNotesCountLittle() {
        var notes = scaleTrack(tonic: 7).notes // G major
        for index in 0..<12 {
            notes.append(note(20 + Double(index) / 16, 20 + Double(index) / 16 + 1/32, UInt8(72 + index)))
        }
        #expect(track(notes).keySignature?.sharps == 1)
    }

    /// Held notes count at most 2 beats, so one long note doesn't decide the key.
    @Test
    func longNotesAreClipped() {
        var notes = scaleTrack(tonic: 0).notes // C major
        notes.append(note(30, 230, 66)) // F♯ held for 200 beats
        #expect(track(notes).keySignature == .natural)
    }

    @Test
    func noEvidence() {
        #expect(track([]).keySignature == nil)

        // Every pitch class with the same weight.
        let chromatic = (0..<12).map { note(Double($0), Double($0) + 1, UInt8(60 + $0)) }
        #expect(track(chromatic).estimateKeySignature() == nil)
    }

    @Test
    func estimate() throws {
        let estimate = try #require(scaleTrack(tonic: 0).estimateKeySignature())
        #expect(estimate.signature == .natural)
        #expect(estimate.correlation > 0.5 && estimate.correlation <= 1)
        #expect(estimate.margin > 0)
    }

    // MARK: KeySignature

    @Test
    func spelling() {
        let signatures = (0..<12).map { IndexedTrack.KeySignature(majorTonic: $0).sharps }
        // C, D♭, D, E♭, E, F, G♭, G, A♭, A, B♭, B
        #expect(signatures == [0, -5, 2, -3, 4, -1, -6, 1, -4, 3, -2, 5])
        #expect(IndexedTrack.KeySignature(majorTonic: -1) == IndexedTrack.KeySignature(majorTonic: 11))
    }

    /// Going through the tonic gives the same signature, or its enharmonic spelling for 6♯, 7♯ and 7♭.
    @Test(arguments: -7...7)
    func majorTonicRoundTrips(sharps: Int) {
        let respelled = IndexedTrack.KeySignature(majorTonic: IndexedTrack.KeySignature(sharps: sharps).majorTonic).sharps
        if (-6...5).contains(sharps) {
            #expect(respelled == sharps)
        } else {
            #expect((respelled - sharps) % 12 == 0)
        }
    }

    /// The accidentals match those of the old `IndexedContainer.KeySignature`.
    @Test
    func matchesTheOldType() {
        for old in IndexedContainer.KeySignature.allCases {
            let new = IndexedTrack.KeySignature(sharps: old.accidental.rawValue * old.pitches.count)
            #expect(new.pitches == old.pitches)
            #expect(new.accidental.rawValue == old.accidental.rawValue)
        }
    }

    /// Every old key signature decodes from its own encoding, and the new format round-trips.
    // MARK: Stored key signatures

    @Test
    func readingAMetaEvent() {
        #expect(MIDIKeySignature(MIDIMetaEvent(timestamp: 0, type: 0x59, data: Data([0xFE, 0])))?.sharps == -2)
        #expect(MIDIKeySignature(MIDIMetaEvent(timestamp: 0, type: 0x59, data: Data([0x07, 1])))?.sharps == 7)
        #expect(MIDIKeySignature(MIDIMetaEvent(timestamp: 0, type: 0x59, data: Data([8, 0]))) == nil)
        #expect(MIDIKeySignature(MIDIMetaEvent(timestamp: 0, type: 0x58, data: Data([2, 0]))) == nil)
        #expect(MIDIKeySignature(MIDIMetaEvent(timestamp: 0, type: 0x59, data: Data())) == nil)
    }

    @Test
    func storedKeySignature() {
        let notes = scaleTrack(tonic: 7).notes
        let inTrack = IndexedTrack(MIDIContainer(tracks: [MIDITrack(notes: notes, metaEvents: [keySignatureEvent(-3, at: 0)])]))
        #expect(inTrack.storedKeySignature?.sharps == -3)

        // Format-1 files keep it in the tempo track.
        let inTempoTrack = IndexedTrack(MIDIContainer(tracks: [MIDITrack(notes: notes)], tempo: MIDITempoTrack(events: [keySignatureEvent(4, at: 0)])))
        #expect(inTempoTrack.storedKeySignature?.sharps == 4)

        // The earliest wins, wherever it is.
        let several = IndexedTrack(MIDIContainer(tracks: [MIDITrack(notes: notes, metaEvents: [keySignatureEvent(2, at: 8), keySignatureEvent(-1, at: 1)])]))
        #expect(several.storedKeySignature?.sharps == -1)

        #expect(track(notes).storedKeySignature == nil)
    }

    @Test
    func storedUnlessNatural() {
        let notes = scaleTrack(tonic: 7).notes // G major, 1 sharp
        func indexed(_ events: [MIDIMetaEvent], notes: [MIDINote]) -> IndexedTrack {
            IndexedTrack(MIDIContainer(tracks: [MIDITrack(notes: notes, metaEvents: events)]))
        }

        #expect(indexed([keySignatureEvent(-3, at: 0)], notes: notes).keySignature?.sharps == -3) // stored wins
        #expect(indexed([keySignatureEvent(0, at: 0)], notes: notes).keySignature?.sharps == 1) // a stored natural is ignored
        #expect(indexed([keySignatureEvent(0, at: 0)], notes: []).keySignature == .natural) // unless the notes give no evidence
        #expect(indexed([], notes: notes).keySignature?.sharps == 1) // nothing stored
    }

    @Test
    func storedKeySignatureSurvivesARoundTrip() {
        let indexed = IndexedTrack(MIDIContainer(tracks: [MIDITrack(notes: scaleTrack(tonic: 0).notes)], tempo: MIDITempoTrack(events: [keySignatureEvent(-2, at: 0)])))
        #expect(IndexedTrack(indexed.makeContainer()).storedKeySignature?.sharps == -2)
    }

    @Test
    func decoding() throws {
        for old in IndexedContainer.KeySignature.allCases {
            let decoded = try JSONDecoder().decode(MIDIKeySignature.self, from: JSONEncoder().encode(old))
            #expect(decoded.sharps == old.accidental.rawValue * old.pitches.count)
            #expect(try JSONDecoder().decode(MIDIKeySignature.self, from: JSONEncoder().encode(decoded)) == decoded)
        }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(MIDIKeySignature.self, from: Data(#"{"pitches":[0],"accidental":1}"#.utf8)) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(MIDIKeySignature.self, from: Data("8".utf8)) }
        #expect(try JSONDecoder().decode(MIDIKeySignature.self, from: Data("-3".utf8)).sharps == -3)
    }

    @Test
    func descriptions() {
        #expect(IndexedTrack.KeySignature(sharps: 3).description == "3♯")
        #expect(IndexedTrack.KeySignature(sharps: -2).description == "2♭")
        #expect(IndexedTrack.KeySignature.natural.description == "♮")
    }

}
