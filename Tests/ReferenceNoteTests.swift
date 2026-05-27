//
//  ReferenceNoteTests.swift
//  MIDIKit
//

@testable
import MIDIKit
import Testing


@Suite("ReferenceNote")
struct ReferenceNoteTests {

    /// Provides a temporary buffer-backed ReferenceNote for testing.
    private func withReferenceNote(
        _ body: (ReferenceNote, UnsafeMutableBufferPointer<MIDINote>) throws -> Void
    ) throws {
        let buffer = UnsafeMutableBufferPointer<MIDINote>.allocate(capacity: 1)
        defer { buffer.deallocate() }
        buffer[0] = MIDINote(onset: 1.0, offset: 2.0, note: 60, velocity: 100)
        let ref = ReferenceNote(buffer.baseAddress!)
        try body(ref, buffer)
    }

    @Test func pointeeGetter() throws {
        try withReferenceNote { ref, _ in
            #expect(ref.pointee.onset == 1.0)
            #expect(ref.pointee.offset == 2.0)
            #expect(ref.pointee.note == 60)
            #expect(ref.pointee.velocity == 100)
        }
    }

    @Test func pointeeSetter() throws {
        try withReferenceNote { ref, buffer in
            ref.pointee = MIDINote(onset: 3.0, offset: 4.0, note: 72, velocity: 50)
            #expect(ref.pointee.onset == 3.0)
            #expect(ref.pointee.note == 72)
            // The underlying buffer is also updated
            #expect(buffer[0].onset == 3.0)
            #expect(buffer[0].note == 72)
        }
    }

    @Test func onsetProxiedFromPointee() throws {
        try withReferenceNote { ref, _ in
            #expect(ref.onset == 1.0)
        }
    }

    @Test func offsetProxiedFromPointee() throws {
        try withReferenceNote { ref, _ in
            #expect(ref.offset == 2.0)
        }
    }

    @Test func offsetProxiedSetter() throws {
        try withReferenceNote { ref, buffer in
            ref.offset = 5.0
            #expect(ref.offset == 5.0)
            #expect(ref.pointee.offset == 5.0)
            #expect(buffer[0].offset == 5.0)
        }
    }

    @Test func durationProxied() throws {
        try withReferenceNote { ref, _ in
            #expect(ref.duration == 1.0)
        }
    }

    @Test func durationProxiedSetter() throws {
        try withReferenceNote { ref, _ in
            ref.duration = 3.0
            #expect(ref.duration == 3.0)
            #expect(ref.offset == 4.0) // onset(1.0) + duration(3.0)
        }
    }

    @Test func noteProxied() throws {
        try withReferenceNote { ref, _ in
            #expect(ref.note == 60)
        }
    }

    @Test func noteProxiedSetter() throws {
        try withReferenceNote { ref, buffer in
            ref.note = 72
            #expect(ref.note == 72)
            #expect(buffer[0].note == 72)
        }
    }

    @Test func pitchProxiedAliasForNote() throws {
        try withReferenceNote { ref, _ in
            #expect(ref.pitch == 60)
            ref.pitch = 48
            #expect(ref.note == 48)
            #expect(ref.pitch == 48)
        }
    }

    @Test func velocityProxied() throws {
        try withReferenceNote { ref, _ in
            #expect(ref.velocity == 100)
            ref.velocity = 64
            #expect(ref.velocity == 64)
        }
    }

    @Test func channelProxied() throws {
        try withReferenceNote { ref, _ in
            #expect(ref.channel == 0)
            ref.channel = 5
            #expect(ref.channel == 5)
        }
    }

    @Test func releaseVelocityProxied() throws {
        try withReferenceNote { ref, _ in
            #expect(ref.releaseVelocity == 0)
        }
    }

    @Test func hashable() throws {
        try withReferenceNote { ref1, _ in
            let ref2 = ReferenceNote(ref1.pointer)
            #expect(ref1 == ref2)
            #expect(ref1.hashValue == ref2.hashValue)
        }
    }

    @Test func notEqualWhenDifferentPointers() throws {
        try withReferenceNote { ref1, _ in
            let otherBuffer = UnsafeMutableBufferPointer<MIDINote>.allocate(capacity: 1)
            defer { otherBuffer.deallocate() }
            otherBuffer[0] = MIDINote(onset: 1.0, offset: 2.0, note: 60, velocity: 100)
            let ref2 = ReferenceNote(otherBuffer.baseAddress!)
            // Same pointee values, but different pointers
            #expect(ref1.pointee == ref2.pointee)
        }
    }

    @Test func comparableByOnset() throws {
        try withReferenceNote { ref, _ in
            let buffer2 = UnsafeMutableBufferPointer<MIDINote>.allocate(capacity: 1)
            defer { buffer2.deallocate() }
            buffer2[0] = MIDINote(onset: 0.5, offset: 1.0, note: 40, velocity: 50)
            let earlier = ReferenceNote(buffer2.baseAddress!)
            #expect(earlier < ref)
            #expect(!(ref < earlier))
        }
    }

}
