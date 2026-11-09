//
//  ChordLegacyTests.swift
//  MIDIKit
//

@testable
import MIDIKit
import Testing
import Foundation


/// Pins the constant-window algorithm: the one an explicit `Chord.Spec(duration:)` selects, which `TimeWarp` relies on and which `Chord.Spec()` was before the generic and transkun algorithms existed.
///
/// The recorded values come from the algorithm as it was before any of that was added. A mismatch means the constant window changed.
@Suite("Chord.ConstantWindow")
struct ChordConstantWindowTests {

    static let seeds: [UInt64] = Array(1 ... 8)
    static let durations: [Double] = [0.03, 0.05, 0.1, 0.2]

    /// `"seed@duration"` to the number of chords and the hash of the partition.
    static let recorded: [String: (chords: Int, hash: UInt64)] = [
        "1@0.03": (213, 0xfb331f89ad81a8aa),
        "1@0.05": (187, 0x88050dd00e27938a),
        "1@0.1": (131, 0x5c971360ac6979fa),
        "1@0.2": (126, 0xa888dcc0e95e5522),
        "2@0.03": (201, 0xf3ce9531e0229c02),
        "2@0.05": (166, 0x5f154cbf92c34eea),
        "2@0.1": (119, 0x6d3c098d274cd7b2),
        "2@0.2": (113, 0x5d00deb896377512),
        "3@0.03": (189, 0xc6b032f44266099c),
        "3@0.05": (160, 0x0c411388c314ded4),
        "3@0.1": (121, 0xf6326ab51c34e0ec),
        "3@0.2": (118, 0x03111be83b180a54),
        "4@0.03": (209, 0x6b8e047c83b9a6c8),
        "4@0.05": (179, 0x60621d10725b1fb8),
        "4@0.1": (132, 0x5cff236ab6942f20),
        "4@0.2": (126, 0x78f85967313f1290),
        "5@0.03": (211, 0xe24bcc5af8795cac),
        "5@0.05": (175, 0x120704465bf0249c),
        "5@0.1": (126, 0xe00129e455244374),
        "5@0.2": (123, 0x533de983f2aa472c),
        "6@0.03": (213, 0x679a00ff032189a5),
        "6@0.05": (187, 0x53beb549455a83e5),
        "6@0.1": (132, 0x1faec5a7b0723ecd),
        "6@0.2": (128, 0x5eaaf7bea93becad),
        "7@0.03": (213, 0x820928874d6854d5),
        "7@0.05": (179, 0xd4d2e05a54f2e885),
        "7@0.1": (132, 0x37835e03b2a5797d),
        "7@0.2": (126, 0xed73a244d57f8b5d),
        "8@0.03": (198, 0x6c938ba731bc7f95),
        "8@0.05": (169, 0xe158ab32f684f49d),
        "8@0.1": (121, 0xff59efa9613055dd),
        "8@0.2": (118, 0xe362f29048cb9fa5),
    ]

    /// `seed` to the hash of the sampled time warp mapping.
    static let recordedWarps: [UInt64: UInt64] = [
        1: 0xa3fb3dda4a8599f6,
        2: 0x7a3f4fa84396e6cd,
        3: 0x105de70294bc5028,
    ]


    @Test func matchesRecordedPartitions() {
        for seed in Self.seeds {
            let indexed = ChordFigures.indexed(ChordFigures.notes(seed: seed))
            for duration in Self.durations {
                let chords = Chord.makeChords(from: indexed, spec: .init(duration: duration))
                let partition = ChordFigures.partition(chords, of: indexed)
                let key = "\(seed)@\(duration)"
                let hash = ChordFigures.hash(partition)
                guard let expected = Self.recorded[key] else {
                    Issue.record("record: \"\(key)\": (\(chords.count), 0x\(String(hash, radix: 16))),")
                    continue
                }
                #expect(chords.count == expected.chords, "\(key)")
                #expect(hash == expected.hash, "\(key)")
            }
            withExtendedLifetime(indexed) {}
        }
    }

    @Test func distinctKeysFollowSingleLinkage() {
        for seed in Self.seeds {
            let indexed = ChordFigures.indexed(ChordFigures.distinctNotes(seed: seed))
            let ordered = ChordFigures.orderedNotes(of: indexed)
            for duration in [0.03, 0.05, 0.1, 0.2] {
                var expected: [[Int]] = [[0]]
                for index in 1 ..< ordered.count {
                    if ordered[index].onset - ordered[index - 1].onset <= duration {
                        expected[expected.count - 1].append(index)
                    } else {
                        expected.append([index])
                    }
                }
                let chords = Chord.makeChords(from: indexed, spec: .init(duration: duration))
                #expect(ChordFigures.partition(chords, of: indexed) == expected, "\(seed)@\(duration)")
            }
            withExtendedLifetime(indexed) {}
        }
    }

    @Test func repeatedKeyNeverSharesAChord() {
        let indexed = ChordFigures.indexed([
            ChordFigures.note(0, 60, duration: 0.02),
            ChordFigures.note(0.03, 64, duration: 0.5),
            ChordFigures.note(0.05, 60, duration: 0.5),
        ])
        let chords = Chord.makeChords(from: indexed, spec: .init(duration: 0.1))
        #expect(ChordFigures.partition(chords, of: indexed) == [[0, 1], [2]])
        #expect(chords.map(\.maxOffset) == [0.05, nil])
        withExtendedLifetime(indexed) {}
    }

    @Test func maxOffsetIsTheEarliestNextOnsetOfTheMembers() {
        for seed in Self.seeds {
            let indexed = ChordFigures.indexed(ChordFigures.notes(seed: seed))
            for duration in Self.durations {
                for chord in Chord.makeChords(from: indexed, spec: .init(duration: duration)) {
                    #expect(chord.maxOffset == ChordFigures.expectedMaxOffset(of: chord, in: indexed), "\(seed)@\(duration)")
                    #expect(chord.maxOffset.map { limit in chord.allSatisfy { $0.onset < limit } } ?? true, "\(seed)@\(duration)")
                }
            }
            withExtendedLifetime(indexed) {}
        }
    }

    @Test func theWindowIsInclusive() {
        func count(from first: Double, to second: Double, duration: Double = 0.1) -> Int {
            let indexed = ChordFigures.indexed([
                ChordFigures.note(first, 60, duration: 0.5),
                ChordFigures.note(second, 67, duration: 0.5),
            ])
            defer { withExtendedLifetime(indexed) {} }
            return Chord.makeChords(from: indexed, spec: .init(duration: duration)).count
        }

        #expect(count(from: 0, to: 0.1) == 1)
        #expect(count(from: 0, to: 0.1000001) == 2)
        // 16.0 - 15.9 is 0.09999999999999964 in floating point: just inside
        #expect(count(from: 15.9, to: 16.0) == 1)
        #expect(count(from: 0, to: 0.06, duration: 0.05) == 2)
        #expect(count(from: 0, to: 0.05, duration: 0.05) == 1)
    }

    @Test func glissandoNeedsElevenShortMonotoneNotes() {
        /// The size of every chord and whether it carries the glissando flag. (Chords point into the container, so only plain values leave this function.)
        func run(_ count: Int, step: Int = 1, duration: Double = 0.1, zigzag: Bool = false) -> [(size: Int, glissando: Bool)] {
            var notes: [MIDINote] = []
            for index in 0 ..< count {
                let offset = zigzag ? (index.isMultiple(of: 2) ? 0 : 7) + index / 2 : index * step
                notes.append(ChordFigures.note(Double(index) * 0.04, 60 + offset, duration: duration))
            }
            let indexed = ChordFigures.indexed(notes)
            defer { withExtendedLifetime(indexed) {} }
            return Chord.makeChords(from: indexed, spec: .init(duration: 0.1)).map { ($0.count, $0.features.contains(.glissando)) }
        }

        for step in [1, -1, 2] {
            let eleven = run(11, step: step)
            #expect(eleven.count == 11, "step \(step)")
            #expect(eleven.allSatisfy { $0.size == 1 && $0.glissando }, "step \(step)")

            let ten = run(10, step: step)
            #expect(ten.count == 1, "step \(step)")
            #expect(ten.allSatisfy { !$0.glissando }, "step \(step)")
        }

        // notes of 0.2 beat or longer are not part of a glissando
        let long = run(12, duration: 0.2)
        #expect(long.allSatisfy { !$0.glissando })
        // a zigzag is not monotone
        let zigzag = run(14, zigzag: true)
        #expect(zigzag.allSatisfy { !$0.glissando })
    }

    @Test func timeWarpIsUnchanged() {
        for seed in Self.seeds.prefix(3) {
            let notes = ChordFigures.notes(seed: seed, events: 40)
            var rng = ChordTestRNG(seed: seed &+ 1000)
            let warped = notes.map { note in
                let onset = note.onset * 1.07 + 0.25 * sin(note.onset * 0.3) + rng.double(-0.01 ... 0.01)
                return MIDINote(onset: onset, offset: onset + note.duration, note: note.note, velocity: note.velocity)
            }
            let mapping = ChordFigures.indexed(notes).timeWarp(other: ChordFigures.indexed(warped))

            var hash: UInt64 = 0xcbf29ce484222325
            for position in stride(from: 0.0, through: 60.0, by: 3.7) {
                let value = Int((mapping.map(position) * 1e6).rounded())
                for shift in stride(from: 0, to: 64, by: 8) {
                    hash ^= UInt64(truncatingIfNeeded: value >> shift) & 0xFF
                    hash = hash &* 0x100000001b3
                }
            }
            guard let expected = Self.recordedWarps[seed] else {
                Issue.record("record warp: \(seed): 0x\(String(hash, radix: 16)),")
                continue
            }
            #expect(hash == expected, "seed \(seed)")
        }
    }

}
