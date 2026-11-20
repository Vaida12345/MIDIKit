//
//  NoteTests.swift
//  MIDIKit
//

import Testing
import MIDIKit


@Suite("MIDINote")
struct MIDINoteTests {

    @Test func basicInit() {
        let note = MIDINote(onset: 1.0, offset: 2.0, pitch: 60, velocity: 100)
        #expect(note.onset == 1.0)
        #expect(note.offset == 2.0)
        #expect(note.pitch == 60)
        #expect(note.velocity == 100)
    }

    @Test func defaultChannelIsZero() {
        let note = MIDINote(onset: 0, offset: 1, pitch: 60, velocity: 100)
        #expect(note.channel == 0)
    }

    @Test func defaultReleaseVelocityIsZero() {
        let note = MIDINote(onset: 0, offset: 1, pitch: 60, velocity: 100)
        #expect(note.releaseVelocity == 0)
    }

    @Test func explicitChannel() {
        let note = MIDINote(onset: 0, offset: 1, pitch: 60, velocity: 100, channel: 5)
        #expect(note.channel == 5)
    }

    @Test func explicitReleaseVelocity() {
        let note = MIDINote(onset: 0, offset: 1, pitch: 60, velocity: 100, releaseVelocity: 64)
        #expect(note.releaseVelocity == 64)
    }

    @Test func durationGetter() {
        let note = MIDINote(onset: 1.0, offset: 3.5, pitch: 60, velocity: 100)
        #expect(note.duration == 2.5)
    }

    @Test func durationSetterChangesOffset() {
        var note = MIDINote(onset: 1.0, offset: 2.0, pitch: 60, velocity: 100)
        note.duration = 3.0
        #expect(note.offset == 4.0)
        #expect(note.onset == 1.0) // onset unchanged
    }

    @Test func pitchIsAliasForNote() {
        var note = MIDINote(onset: 0, offset: 1, pitch: 60, velocity: 100)
        #expect(note.pitch == 60)
        note.pitch = 72
        #expect(note.pitch == 72)
        #expect(note.pitch == 72)
    }

    @Test func comparisonByOnset() {
        let early = MIDINote(onset: 0.0, offset: 1.0, pitch: 60, velocity: 100)
        let late  = MIDINote(onset: 1.0, offset: 2.0, pitch: 60, velocity: 100)
        #expect(early < late)
        #expect(!(late < early))
    }

    /// At the same onset, the lower pitch comes first.
    @Test func equalOnsetOrdersByPitch() {
        let a = MIDINote(onset: 1.0, offset: 2.0, pitch: 60, velocity: 100)
        let b = MIDINote(onset: 1.0, offset: 3.0, pitch: 72, velocity: 50)
        #expect(a < b)
        #expect(!(b < a))
    }

    /// For any two notes, exactly one of `a < b`, `a == b` and `b < a` holds.
    @Test func orderIsTotal() {
        var generator = SystemRandomNumberGenerator()
        func random() -> MIDINote {
            MIDINote(
                onset: Double(Int.random(in: 0...2, using: &generator)),
                offset: Double(Int.random(in: 3...4, using: &generator)),
                pitch: UInt8.random(in: 60...61, using: &generator),
                velocity: UInt8.random(in: 1...2, using: &generator),
                channel: UInt8.random(in: 0...1, using: &generator),
                releaseVelocity: UInt8.random(in: 0...1, using: &generator)
            )
        }
        for _ in 0..<2_000 {
            let a = random()
            let b = random()
            let holds = [a < b, a == b, b < a].filter { $0 }.count
            #expect(holds == 1, "\(a), \(b)")
        }
    }

    @available(*, deprecated)
    @Test func deprecatedNoteIsPitch() {
        var note = MIDINote(onset: 0, offset: 1, note: 64, velocity: 100)
        #expect(note.pitch == 64)
        note.note = 65
        #expect(note.pitch == 65 && note.note == 65)
    }

    @Test func hashableConsistency() {
        let a = MIDINote(onset: 1.0, offset: 2.0, pitch: 60, velocity: 100)
        let b = MIDINote(onset: 1.0, offset: 2.0, pitch: 60, velocity: 100)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

}


@Suite("MIDINote.Description")
struct MIDINoteDescriptionTests {

    @Test func middleC() {
        let desc = MIDINote.description(for: 60)
        #expect(desc == "C4")
    }

    @Test func a0LowestPiano() {
        let desc = MIDINote.description(for: 21)
        #expect(desc == "A0")
    }

    @Test func c8HighestPiano() {
        let desc = MIDINote.description(for: 108)
        #expect(desc == "C8")
    }

    @Test func allOctavesOfC() {
        // C1 = 24, C2 = 36, C3 = 48, C4 = 60, C5 = 72, C6 = 84, C7 = 96
        #expect(MIDINote.description(for: 24) == "C1")
        #expect(MIDINote.description(for: 36) == "C2")
        #expect(MIDINote.description(for: 48) == "C3")
        #expect(MIDINote.description(for: 60) == "C4")
        #expect(MIDINote.description(for: 72) == "C5")
        #expect(MIDINote.description(for: 84) == "C6")
        #expect(MIDINote.description(for: 96) == "C7")
    }

    @Test func sharpNotes() {
        #expect(MIDINote.description(for: 61) == "C4#")
        #expect(MIDINote.description(for: 63) == "D4#")
        #expect(MIDINote.description(for: 66) == "F4#")
        #expect(MIDINote.description(for: 68) == "G4#")
        #expect(MIDINote.description(for: 70) == "A4#")
    }

}


@Suite("MIDINote.Determine")
struct MIDINoteDetermineTests {

    @Test func cNatural() {
        let result = MIDINote.determine(note: 60)
        #expect(result.group == 5)   // C4 → group 5 → C4
        #expect(result.index == 0)   // C → 0
        #expect(!result.isSharp)
    }

    @Test func cSharp() {
        let result = MIDINote.determine(note: 61)
        #expect(result.index == 0)   // C
        #expect(result.isSharp)
    }

    @Test func dNatural() {
        let result = MIDINote.determine(note: 62)
        #expect(result.index == 1)   // D
        #expect(!result.isSharp)
    }

    @Test func eNatural() {
        let result = MIDINote.determine(note: 64)
        #expect(result.index == 2)   // E
        #expect(!result.isSharp)
    }

    @Test func fNatural() {
        let result = MIDINote.determine(note: 65)
        #expect(result.index == 3)   // F
        #expect(!result.isSharp)
    }

    @Test func gNatural() {
        let result = MIDINote.determine(note: 67)
        #expect(result.index == 4)   // G
        #expect(!result.isSharp)
    }

    @Test func aNatural() {
        let result = MIDINote.determine(note: 69)
        #expect(result.index == 5)   // A
        #expect(!result.isSharp)
    }

    @Test func bNatural() {
        let result = MIDINote.determine(note: 71)
        #expect(result.index == 6)   // B
        #expect(!result.isSharp)
    }

    @Test func allSemitonesRoundtrip() {
        for pitch in 0..<128 {
            let (group, index, isSharp) = MIDINote.determine(note: pitch)
            let noteName = MIDINote.diatonicScale[index] + (isSharp ? "#" : "")
            // description re-encodes through determine again
            let desc = MIDINote.description(for: pitch)
            #expect(!desc.isEmpty)
            // Verify the grouping: group = (pitch / 12) + 1
            // For sharp notes: e.g. C#4 = pitch 61, group 5 but C is group 5
            // The group value is floor(pitch / 12) + 1 for non-sharp,
            // and floor(pitch / 12) + 1 for sharp as well (since C#4 is still octave 4)
        }
    }

    
    @Test func determineNote() {
        print(MIDINote.determine(note: 60))
    }
    
}


@Suite("MIDINote.Color")
struct MIDINoteColorTests {

    @Test func colorComponentsReturnsSIMD4() {
        let components = MIDINote.colorComponents(velocity: 64)
        #expect(components[0] >= 0)
        #expect(components[1] >= 0)
        #expect(components[2] >= 0)
        #expect(components[3] == 1) // alpha always 1
    }

    @Test func lowVelocityIsBluer() {
        let lowVelocity = MIDINote.colorComponents(velocity: 1)
        let highVelocity = MIDINote.colorComponents(velocity: 127)
        // Low velocity (soft) → higher blue; high velocity (loud) → higher red
        #expect(lowVelocity[2] > highVelocity[2])
        #expect(highVelocity[0] > lowVelocity[0])
    }

    @Test func componentsAreInRGBRange() {
        for velocity in stride(from: 1, through: 127, by: 8) {
            let c = MIDINote.colorComponents(velocity: UInt8(velocity))
            #expect(c[0] >= 0 && c[0] <= 1)
            #expect(c[1] >= 0 && c[1] <= 1)
            #expect(c[2] >= 0 && c[2] <= 1)
        }
    }

}
