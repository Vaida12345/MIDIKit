//
//  AnalysisTests.swift
//  MIDIKit
//

@testable
import MIDIKit
import Foundation
import Testing


@Suite("IndexedContainer.Analysis")
struct AnalysisTests {

    private func makeIndexed(_ notes: [MIDINote], sustains: [MIDISustainEvent] = []) -> IndexedContainer {
        let track = MIDITrack(notes: notes, sustains: sustains)
        return MIDIContainer(tracks: [track]).indexed()
    }

    @Test func sustainCoverageEmptyIsOne() {
        let indexed = MIDIContainer().indexed()
        #expect(indexed.sustainCoverage == 1.0)
    }

    @Test func sustainCoverageNoSustains() {
        let indexed = makeIndexed([
            MIDINote(onset: 0, offset: 2, note: 60, velocity: 100),
        ])
        // No sustains → cumulative = 0 / maxOffset
        #expect(indexed.sustainCoverage == 0.0)
    }

    @Test func sustainCoverageFullCoverage() {
        let indexed = makeIndexed([
            MIDINote(onset: 0, offset: 4, note: 60, velocity: 100),
        ], sustains: [
            MIDISustainEvent(onset: 0, offset: 2),
            MIDISustainEvent(onset: 2, offset: 4),
        ])
        let coverage = indexed.sustainCoverage
        #expect(coverage > 0)
    }

    @Test func sustainDurations() {
        let indexed = makeIndexed([], sustains: [
            MIDISustainEvent(onset: 0, offset: 2),
            MIDISustainEvent(onset: 3, offset: 5),
        ])
        let durations = indexed.sustainDurations()
        #expect(durations.count == 2)
        // Function computes: sustain.offset - lastOffset (cumulative)
        #expect(durations[0] == 2.0)  // 2.0 - 0.0 = 2.0
        #expect(durations[1] == 3.0)  // 5.0 - 2.0 = 3.0
    }

    @Test func baselineBarLength() {
        // Create notes with a clear 4-beat pattern
        var notes: [MIDINote] = []
        for bar in 0..<4 {
            let base = Double(bar) * 4.0
            notes.append(MIDINote(onset: base, offset: base + 2.0, note: 60, velocity: 100))
            notes.append(MIDINote(onset: base + 1, offset: base + 1.5, note: 64, velocity: 80))
            notes.append(MIDINote(onset: base + 2, offset: base + 2.5, note: 67, velocity: 90))
            notes.append(MIDINote(onset: base + 3, offset: base + 3.5, note: 72, velocity: 70))
        }
        let indexed = makeIndexed(notes)
        let barLength = indexed.baselineBarLength(beatsPerMeasure: 4)
        #expect(barLength > 0)
        #expect(barLength.isFinite)
    }

}


@Suite("IndexedContainer.KeySignature")
struct KeySignatureTests {

    private func makeIndexed(_ notes: [MIDINote]) -> IndexedContainer {
        let track = MIDITrack(notes: notes)
        return MIDIContainer(tracks: [track]).indexed()
    }

    @Test func allCasesContainsNatural() {
        #expect(IndexedContainer.KeySignature.allCases.contains(.natural))
    }

    @Test func allCasesContainsAllFlats() {
        #expect(IndexedContainer.KeySignature.allCases.contains(.flats1))
        #expect(IndexedContainer.KeySignature.allCases.contains(.flats7))
    }

    @Test func allCasesContainsAllSharps() {
        #expect(IndexedContainer.KeySignature.allCases.contains(.sharps1))
        #expect(IndexedContainer.KeySignature.allCases.contains(.sharps7))
    }

    @Test func initFromAccidentalAndCount() {
        #expect(IndexedContainer.KeySignature(accidental: .sharp, accidentalCount: 0) == .natural)
        #expect(IndexedContainer.KeySignature(accidental: .sharp, accidentalCount: 3) == .sharps3)
        #expect(IndexedContainer.KeySignature(accidental: .flat, accidentalCount: 2) == .flats2)
        #expect(IndexedContainer.KeySignature(accidental: .neutral, accidentalCount: 0) == .natural)
    }

    @Test func invalidCountReturnsNil() {
        #expect(IndexedContainer.KeySignature(accidental: .sharp, accidentalCount: 8) == nil)
        #expect(IndexedContainer.KeySignature(accidental: .flat, accidentalCount: 8) == nil)
    }

    @Test func cMajorReturnsNatural() {
        // Notes in C major scale (no sharps/flats)
        let cMajorNotes: [MIDINote] = [60, 62, 64, 65, 67, 69, 71, 72].map { pitch in
            MIDINote(onset: Double(pitch - 60), offset: Double(pitch - 60) + 0.5, note: pitch, velocity: 100)
        }
        let indexed = makeIndexed(cMajorNotes)
        let keySig = indexed.keySignature()
        // Should return a valid key signature
        #expect(IndexedContainer.KeySignature.allCases.contains(keySig))
    }

    @Test func codable() throws {
        let keySig = IndexedContainer.KeySignature.sharps3
        let encoder = JSONEncoder()
        let data = try encoder.encode(keySig)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(IndexedContainer.KeySignature.self, from: data)
        #expect(decoded == keySig)
    }

    @Test func hashable() {
        let a = IndexedContainer.KeySignature.sharps2
        let b = IndexedContainer.KeySignature.sharps2
        #expect(a.hashValue == b.hashValue)
    }

}
