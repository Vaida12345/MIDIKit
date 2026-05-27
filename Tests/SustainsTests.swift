//
//  SustainsTests.swift
//  MIDIKit
//

import MIDIKit
import Testing


@Suite("MIDISustainEvent")
struct MIDISustainEventTests {

    @Test func basicInit() {
        let sustain = MIDISustainEvent(onset: 1.0, offset: 3.0)
        #expect(sustain.onset == 1.0)
        #expect(sustain.offset == 3.0)
    }

    @Test func durationGetter() {
        let sustain = MIDISustainEvent(onset: 1.0, offset: 4.0)
        #expect(sustain.duration == 3.0)
    }

    @Test func durationSetterChangesOffset() {
        var sustain = MIDISustainEvent(onset: 1.0, offset: 3.0)
        sustain.duration = 5.0
        #expect(sustain.offset == 6.0)
        #expect(sustain.onset == 1.0)
    }

    @Test func equatable() {
        let a = MIDISustainEvent(onset: 1.0, offset: 2.0)
        let b = MIDISustainEvent(onset: 1.0, offset: 2.0)
        #expect(a == b)
    }

    @Test func notEqualDifferentValues() {
        let a = MIDISustainEvent(onset: 1.0, offset: 2.0)
        let b = MIDISustainEvent(onset: 1.0, offset: 3.0)
        #expect(a != b)
    }

    @Test func comparableByOnset() {
        let early = MIDISustainEvent(onset: 0.0, offset: 1.0)
        let late  = MIDISustainEvent(onset: 2.0, offset: 3.0)
        #expect(early < late)
    }

    @Test func hashable() {
        let a = MIDISustainEvent(onset: 1.0, offset: 2.0)
        let b = MIDISustainEvent(onset: 1.0, offset: 2.0)
        #expect(a.hashValue == b.hashValue)
    }

}


@Suite("MIDISustainEvents")
struct MIDISustainEventsTests {

    @Test func initEmpty() {
        let sustains = MIDISustainEvents()
        #expect(sustains.isEmpty)
        #expect(sustains.count == 0)
    }

    @Test func initSortsByOnset() {
        let sustains = MIDISustainEvents([
            MIDISustainEvent(onset: 3.0, offset: 4.0),
            MIDISustainEvent(onset: 1.0, offset: 2.0),
            MIDISustainEvent(onset: 2.0, offset: 3.0),
        ])
        #expect(sustains[0].onset == 1.0)
        #expect(sustains[1].onset == 2.0)
        #expect(sustains[2].onset == 3.0)
    }

    @Test func insertSingle() {
        var sustains = MIDISustainEvents([
            MIDISustainEvent(onset: 1.0, offset: 2.0),
            MIDISustainEvent(onset: 4.0, offset: 5.0),
        ])
        sustains.insert(MIDISustainEvent(onset: 2.5, offset: 3.0))
        #expect(sustains.count == 3)
        #expect(sustains[0].onset == 1.0)
        #expect(sustains[1].onset == 2.5)
        #expect(sustains[2].onset == 4.0)
    }

    @Test func insertAtBeginning() {
        var sustains = MIDISustainEvents([
            MIDISustainEvent(onset: 2.0, offset: 3.0),
        ])
        sustains.insert(MIDISustainEvent(onset: 0.0, offset: 1.0))
        #expect(sustains[0].onset == 0.0)
        #expect(sustains[1].onset == 2.0)
    }

    @Test func insertAtEnd() {
        var sustains = MIDISustainEvents([
            MIDISustainEvent(onset: 1.0, offset: 2.0),
        ])
        sustains.insert(MIDISustainEvent(onset: 5.0, offset: 6.0))
        #expect(sustains[1].onset == 5.0)
    }

    @Test func insertContentsOf() {
        var sustains = MIDISustainEvents([
            MIDISustainEvent(onset: 1.0, offset: 2.0),
        ])
        sustains.insert(contentsOf: MIDISustainEvents([
            MIDISustainEvent(onset: 0.5, offset: 0.8),
            MIDISustainEvent(onset: 3.0, offset: 4.0),
        ]))
        #expect(sustains.count == 3)
        #expect(sustains[0].onset == 0.5)
        #expect(sustains[1].onset == 1.0)
        #expect(sustains[2].onset == 3.0)
    }

    @Test func iteration() {
        let sustains = MIDISustainEvents([
            MIDISustainEvent(onset: 1.0, offset: 2.0),
            MIDISustainEvent(onset: 3.0, offset: 4.0),
        ])
        var collected: [MIDISustainEvent] = []
        for s in sustains {
            collected.append(s)
        }
        #expect(collected.count == 2)
    }

    @Test func equatable() {
        let a = MIDISustainEvents([MIDISustainEvent(onset: 1, offset: 2)])
        let b = MIDISustainEvents([MIDISustainEvent(onset: 1, offset: 2)])
        #expect(a == b)
    }

}
