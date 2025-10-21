//
//  TransformTests.swift
//  MIDIKit
//
//  Created by Vaida on 2025-10-22.
//

import Testing
import MIDIKit


@Suite("Transform")
struct TransformTests {
    
    @Test
    func mergeNotesInSameInterval() async {
        let lhs = MIDIContainer(notes: [
            MIDINote(onset: 0, offset: 1, note: 60, velocity: 10),
            MIDINote(onset: 2, offset: 3, note: 60, velocity: 10),
        ])
        let rhs = MIDIContainer(notes: [
            MIDINote(onset: 0, offset: 3, note: 60, velocity: 10),
        ])
        let indexed = lhs.indexed()
        await indexed.mergeNotesInSameInterval(in: rhs.indexed(), threshold: 70, difference: 0)
        let transformed = indexed.makeContainer()
        #expect(transformed == rhs)
    }
    
}
