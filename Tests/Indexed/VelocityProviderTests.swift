//
//  VelocityProviderTests.swift
//  MIDIKit
//
//  Created by Codex on 2026-04-02.
//

@testable
import MIDIKit
import Testing


@Suite("VelocityProvider")
struct VelocityProviderTests {

    @Test
    func infersFromExactPitchSequenceFirst() {
        let indexed = Self.makeIndexed(notes: [
            MIDINote(onset: 1.0, offset: 1.5, note: 60, velocity: 90),
            MIDINote(onset: 2.0, offset: 2.5, note: 60, velocity: 75),
            MIDINote(onset: 1.0, offset: 1.5, note: 67, velocity: 40),
        ])
        let provider = indexed.makeVelocityProvider()

        let inferred = provider.inferVelocity(pitch: 60, onset: 1.6, tolerance: 0.2)
        #expect(inferred == 90)
    }

    @Test
    func fallsBackToChromaWhenPitchMissing() {
        let indexed = Self.makeIndexed(notes: [
            MIDINote(onset: 2.0, offset: 2.4, note: 72, velocity: 70),
        ])
        let provider = indexed.makeVelocityProvider()

        let inferred = provider.inferVelocity(pitch: 60, onset: 2.45, tolerance: 0.2)
        #expect(inferred == 70)
    }

    @Test
    func fallsBackToGlobalWhenChromaMissing() {
        let indexed = Self.makeIndexed(notes: [
            MIDINote(onset: 3.0, offset: 3.2, note: 61, velocity: 55),
        ])
        let provider = indexed.makeVelocityProvider()

        let inferred = provider.inferVelocity(pitch: 74, onset: 3.25, tolerance: 0.2)
        #expect(inferred == 55)
    }

    @Test
    func outsideToleranceUsesPreviousGlobalValue() {
        let indexed = Self.makeIndexed(notes: [
            MIDINote(onset: 1.0, offset: 1.2, note: 60, velocity: 20),
            MIDINote(onset: 2.0, offset: 2.2, note: 64, velocity: 80),
        ])
        let provider = indexed.makeVelocityProvider()

        let inferred = provider.inferVelocity(pitch: 30, onset: 10.0, tolerance: 0.01)
        #expect(inferred == 80)
    }

    @Test
    func emptySourceReturnsZero() {
        let provider = Self.makeIndexed(notes: []).makeVelocityProvider()
        #expect(provider.inferVelocity(pitch: 60, onset: 0.0) == 0)
    }

    @Test
    func binarySearchHelpersRespectStrictInequalities() {
        let sequence: [IndexedContainer.VelocityProvider.VelocityDataPoint] = [
            .init(onset: 1.0, duration: 0.5, velocity: 10),
            .init(onset: 3.0, duration: 0.5, velocity: 20),
            .init(onset: 5.0, duration: 0.5, velocity: 30),
        ]

        #expect(sequence.firstIndex(after: 3.0) == 2)
        #expect(sequence.firstIndex(after: 5.0) == nil)

        #expect(sequence.lastIndex(before: 1.4) == nil)
        #expect(sequence.lastIndex(before: 1.6) == 0)
        #expect(sequence.lastIndex(before: 6.0) == 2)
    }

}


private extension VelocityProviderTests {

    static func makeIndexed(notes: [MIDINote]) -> IndexedContainer {
        let track = MIDITrack(notes: notes)
        let container = MIDIContainer(tracks: [track])
        return container.indexed()
    }

}
