//
//  ChordTestSupport.swift
//  MIDIKit
//

@testable
import MIDIKit
import Foundation


/// A small deterministic generator, so the figures the chord tests use never change.
struct ChordTestRNG {

    var state: UInt64

    init(seed: UInt64) {
        self.state = seed &* 0x9E3779B97F4A7C15 &+ 0x1234567
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }

    mutating func double(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }

}


/// Music-like material for the chord tests. Everything is in beats; an `IndexedContainer` is always 120 BPM, so 0.1 beat is 50 ms.
enum ChordFigures {

    static func note(_ onset: Double, _ key: Int, duration: Double, velocity: Int = 80) -> MIDINote {
        MIDINote(onset: onset, offset: onset + duration, note: UInt8(key), velocity: UInt8(velocity))
    }

    static func indexed(_ notes: [MIDINote]) -> IndexedContainer {
        MIDIContainer(tracks: [MIDITrack(notes: notes)]).indexed()
    }

    /// A mix of single notes, chords with a small spread, monotone runs, trills, repeated keys and chords just apart. Figures overlap now and then, as they do in dense music.
    static func notes(seed: UInt64, events: Int = 60) -> [MIDINote] {
        var rng = ChordTestRNG(seed: seed)
        var notes: [MIDINote] = []
        var time = 0.0

        for _ in 0 ..< events {
            time += rng.double(0.1 ... 0.9)
            switch rng.int(0 ... 6) {
            case 0:
                notes.append(note(time, rng.int(40 ... 84), duration: rng.double(0.05 ... 1.5), velocity: rng.int(30 ... 120)))

            case 1, 6:
                let spread = [0.0, 0.02, 0.05, 0.09][rng.int(0 ... 3)]
                var keys = Set<Int>()
                let size = rng.int(2 ... 5)
                while keys.count < size { keys.insert(rng.int(36 ... 88)) }
                for key in keys.sorted() {
                    notes.append(note(time + rng.double(0 ... spread), key, duration: rng.double(0.05 ... 1.5), velocity: rng.int(30 ... 120)))
                }

            case 2:
                // a monotone run of short notes; 11 or more of them are a glissando
                let count = rng.int(5 ... 14)
                let direction = rng.int(0 ... 1) == 0 ? 1 : -1
                let step = rng.int(1 ... 4)
                let spacing = rng.double(0.02 ... 0.09)
                var key = rng.int(48 ... 72)
                for index in 0 ..< count {
                    notes.append(note(time + Double(index) * spacing, key, duration: rng.double(0.04 ... 0.15), velocity: rng.int(30 ... 120)))
                    key = Swift.min(108, Swift.max(21, key + direction * step))
                }

            case 3:
                let low = rng.int(40 ... 80)
                let high = low + rng.int(1 ... 2)
                let spacing = rng.double(0.03 ... 0.08)
                for index in 0 ..< rng.int(4 ... 9) {
                    notes.append(note(time + Double(index) * spacing, index.isMultiple(of: 2) ? low : high, duration: rng.double(0.03 ... 0.12), velocity: rng.int(30 ... 120)))
                }

            case 4:
                let key = rng.int(40 ... 84)
                notes.append(note(time, key, duration: 0.02, velocity: 70))
                notes.append(note(time + rng.double(0.015 ... 0.09), key, duration: rng.double(0.05 ... 0.5), velocity: 90))

            default:
                var keys = Set<Int>()
                let size = rng.int(2 ... 4)
                while keys.count < size { keys.insert(rng.int(36 ... 88)) }
                let gap = rng.double(0.08 ... 0.14)
                for key in keys.sorted() {
                    notes.append(note(time, key, duration: rng.double(0.05 ... 1)))
                    notes.append(note(time + gap, key + (key < 100 ? 1 : -1), duration: rng.double(0.05 ... 1)))
                }
            }
        }
        return notes
    }

    /// Notes that never repeat a key, so a chord is a run of notes whose consecutive onsets are close enough.
    static func distinctNotes(seed: UInt64) -> [MIDINote] {
        var rng = ChordTestRNG(seed: seed)
        var keys = Array(21 ... 108)
        for index in keys.indices.dropLast() { keys.swapAt(index, index + rng.int(0 ... (keys.count - 1 - index))) }

        var notes: [MIDINote] = []
        var time = 0.0
        for key in keys.prefix(70) {
            switch rng.int(0 ... 3) {
            case 0: break
            case 1: time += rng.double(0.005 ... 0.05)
            case 2: time += rng.double(0.06 ... 0.3)
            default: time += rng.double(0.5 ... 2)
            }
            notes.append(note(time, key, duration: rng.double(0.2 ... 1.5)))
        }
        return notes
    }

    /// The notes with a tenth of a millisecond of seeded noise on every onset.
    ///
    /// Exactly equal gaps (a trill, a scale in strict time) make two margins of the arbiter tie, and a rounding error in the last bit of an onset then decides which pair is the weaker. With the noise no two margins tie, so the answer follows from the figures and not from the rounding of this machine's arithmetic.
    static func jittered(_ notes: [MIDINote], seed: UInt64) -> [MIDINote] {
        var rng = ChordTestRNG(seed: seed &+ 500)
        return notes.map { note in
            let noise = rng.double(-0.0002 ... 0.0002)
            return MIDINote(onset: note.onset + noise, offset: note.offset + noise, note: note.note, velocity: note.velocity)
        }
    }

    /// Evenly spaced notes of unrelated keys. No pair stands apart from its neighbors, no key repeats within 49 notes, and nothing is a run: the steps are 19 semitones up or 30 down.
    static func stream(count: Int, spacingMs: Double, duration: Double = 0.05, from start: Double = 0) -> [MIDINote] {
        (0 ..< count).map { index in
            note(start + Double(index) * spacingMs / 500, 36 + (index * 19) % 49, duration: duration)
        }
    }

    /// Surrounds a figure with a note 400 ms before and 400 ms after, far from its keys. Without them the figure sits at the edge of the piece, where the silence around a pair makes it likelier a chord.
    static func framed(_ figure: [MIDINote]) -> [MIDINote] {
        let start = figure.map(\.onset).min()!
        let end = figure.map(\.onset).max()!
        return [note(start - 0.8, 24, duration: 0.05)] + figure + [note(end + 0.8, 100, duration: 0.05)]
    }

    /// `count` pairs, `gap` beats apart within a pair and a second (2 beats) between pairs. The registers alternate two octaves apart, so no two pairs form an interval with each other: only the keys within a pair relate.
    static func pairs(count: Int, low: Int, high: Int, gap: Double, firstDuration: Double, secondVelocity: Int = 80) -> [MIDINote] {
        var notes: [MIDINote] = []
        for index in 0 ..< count {
            let shift = index.isMultiple(of: 2) ? -12 : 12
            let start = 1 + Double(index) * 2
            notes.append(note(start, low + shift, duration: firstDuration))
            notes.append(note(start + gap, high + shift, duration: 0.5, velocity: secondVelocity))
        }
        return notes
    }

    /// The notes with the lengths drawn again, from an instant to several seconds, and the velocities drawn from `20 ... 120` (once, so a second call with the same seed gives the same velocities). Only for notes that never repeat a key, where any length is valid.
    static func withOtherOffsets(_ notes: [MIDINote], seed: UInt64) -> (velocitiesOnly: [MIDINote], rewritten: [MIDINote]) {
        var rng = ChordTestRNG(seed: seed &+ 4242)
        let louder = notes.map { MIDINote(onset: $0.onset, offset: $0.offset, note: $0.note, velocity: UInt8(rng.int(20 ... 120))) }
        let rewritten = louder.map { MIDINote(onset: $0.onset, offset: $0.onset + rng.double(0.001 ... 6), note: $0.note, velocity: $0.velocity) }
        return (louder, rewritten)
    }

    /// The number of chords. (Chords point into the container, so only plain values leave this function.)
    static func chordCount(_ notes: [MIDINote], optimizeFor algorithm: TranscriptionAlgorithm? = nil, spec: Chord.Spec = Chord.Spec()) -> Int {
        sizes(notes, optimizeFor: algorithm, spec: spec).count
    }

    /// The size of every chord, in order.
    static func sizes(_ notes: [MIDINote], optimizeFor algorithm: TranscriptionAlgorithm? = nil, spec: Chord.Spec = Chord.Spec()) -> [Int] {
        let container = indexed(notes)
        defer { withExtendedLifetime(container) {} }
        return Chord.makeChords(from: container, spec: spec, optimizeFor: algorithm).map(\.count)
    }

    /// Every note of the container, ordered by onset and then key, which is a total order because a key never sounds twice at once.
    static func orderedNotes(of indexed: IndexedContainer) -> [ReferenceNote] {
        indexed.notes.values.flatMap { $0.contents }.sorted { ($0.onset, $0.note) < ($1.onset, $1.note) }
    }

    /// The chords as lists of positions in `orderedNotes(of:)`, each ascending, the chords ordered by their first member.
    static func partition(_ chords: [Chord], of indexed: IndexedContainer) -> [[Int]] {
        var position: [ReferenceNote: Int] = [:]
        for (index, note) in orderedNotes(of: indexed).enumerated() { position[note] = index }
        return chords.map { chord in chord.contents.map { position[$0]! }.sorted() }.sorted { $0[0] < $1[0] }
    }

    /// 64-bit FNV-1a over the partition.
    static func hash(_ partition: [[Int]]) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        func feed(_ value: Int) {
            for shift in stride(from: 0, to: 64, by: 8) {
                hash ^= UInt64(truncatingIfNeeded: value >> shift) & 0xFF
                hash = hash &* 0x100000001b3
            }
        }
        for chord in partition {
            for position in chord { feed(position) }
            feed(-1)
        }
        return hash
    }

    /// The oracle for `Chord.maxOffset`: the earliest onset of the next note on the same key among the members.
    static func expectedMaxOffset(of chord: Chord, in indexed: IndexedContainer) -> Double? {
        var result: Double?
        for member in chord.contents {
            let sameKey = indexed.notes[member.note]!.contents
            guard let index = sameKey.firstIndex(of: member), index + 1 < sameKey.count else { continue }
            let next = sameKey[index + 1].onset
            result = result.map { Swift.min($0, next) } ?? next
        }
        return result
    }

}
