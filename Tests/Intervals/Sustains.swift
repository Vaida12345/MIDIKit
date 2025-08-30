//
//  Sustains.swift
//  MIDIKit
//
//  Created by Vaida on 2025-08-30.
//

import MIDIKit
import Testing


@Suite
struct SustainsTests {
    
    @Test func insert() {
        var sustains = MIDISustainEvents([MIDISustainEvent(onset: 1, offset: 3)])
        sustains.insert(MIDISustainEvent(onset: 6, offset: 7))
        #expect(sustains.contents == [.init(onset: 1, offset: 3), .init(onset: 6, offset: 7)])
        sustains.insert(MIDISustainEvent(onset: 4, offset: 5))
        #expect(sustains.contents == [.init(onset: 1, offset: 3), .init(onset: 4, offset: 5), .init(onset: 6, offset: 7)])
        sustains.insert(MIDISustainEvent(onset: 0, offset: 0.5))
        #expect(sustains.contents == [.init(onset: 0, offset: 0.5), .init(onset: 1, offset: 3), .init(onset: 4, offset: 5), .init(onset: 6, offset: 7)])
    }
    
}
