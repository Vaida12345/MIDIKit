//
//  ChordArbiterTests.swift
//  MIDIKit
//

@testable
import MIDIKit
import Testing
import Foundation


/// The algorithm `Chord.Spec()` selects: the generic arbiter, or the arbiter of a transcription algorithm when asked for.
///
/// The figures sit well away from any decision boundary of the tuned parameters, or find the boundary by search, so a retune only moves the numbers that pin the recorded partitions.
@Suite("Chord.Arbiter")
struct ChordArbiterTests {

    /// Generic, and every transcription algorithm.
    static let algorithms: [TranscriptionAlgorithm?] = [nil] + TranscriptionAlgorithm.allCases.map { Optional($0) }
    static let seeds: [UInt64] = Array(1 ... 8)

    typealias Figures = ChordFigures

    /// `"algorithm/seed"` to the number of chords and the hash of the partition.
    ///
    /// A mismatch means the algorithm or its tuned parameters changed. After a deliberate retune, replace the values the failure prints.
    static let recorded: [String: (chords: Int, hash: UInt64)] = [
        "generic/1": (160, 0x6d1d8ba9f8fb9992),
        "generic/2": (145, 0x22fc011860238882),
        "generic/3": (147, 0xcac1ba21dcf1714c),
        "generic/4": (159, 0x8a94aface8817838),
        "generic/5": (154, 0xf2842b0fefaadd24),
        "generic/6": (150, 0xc44e1661644a7cfd),
        "generic/7": (158, 0x4b43b8fe786912ad),
        "generic/8": (147, 0xf187cdfb7be3a6ed),
        "transkun/1": (166, 0x53fe2d297ecbf6c2),
        "transkun/2": (149, 0xa39dd97c00d6ed52),
        "transkun/3": (151, 0x01e3572b7b06de6c),
        "transkun/4": (163, 0x4e9e5f4e717f78a8),
        "transkun/5": (161, 0xf5fc558e5c9ca61c),
        "transkun/6": (157, 0xa7b59bb29ffdfae5),
        "transkun/7": (164, 0xc68ec702e81a00bd),
        "transkun/8": (151, 0xae1a19c999a5872d),
        "pianoTranscription/1": (155, 0xf6fff52623a760fa),
        "pianoTranscription/2": (139, 0xace40ae854168a32),
        "pianoTranscription/3": (140, 0x86edb8ac17155b14),
        "pianoTranscription/4": (153, 0x1b0bdb581805948),
        "pianoTranscription/5": (150, 0x1bf1349133a2f664),
        "pianoTranscription/6": (145, 0x9a4833011446a985),
        "pianoTranscription/7": (153, 0xc2af719bd3f07805),
        "pianoTranscription/8": (140, 0x551ae4c5be7f7065),
    ]


    // MARK: - API

    @Test func transcriptionAlgorithmAPI() throws {
        #expect(TranscriptionAlgorithm.allCases == [.transkun, .pianoTranscription])
        #expect(TranscriptionAlgorithm.transkun.rawValue == "transkun")
        #expect(TranscriptionAlgorithm.pianoTranscription.rawValue == "pianoTranscription")
        #expect(TranscriptionAlgorithm(rawValue: "transkun") == .transkun)
        #expect(TranscriptionAlgorithm(rawValue: "pianoTranscription") == .pianoTranscription)
        #expect(TranscriptionAlgorithm(rawValue: "unknown") == nil)

        for algorithm in TranscriptionAlgorithm.allCases {
            let data = try JSONEncoder().encode(algorithm)
            #expect(String(decoding: data, as: UTF8.self) == "\"\(algorithm.rawValue)\"")
            #expect(try JSONDecoder().decode(TranscriptionAlgorithm.self, from: data) == algorithm)
        }

        func requireSendable<T: Sendable>(_ value: T) {}
        requireSendable(TranscriptionAlgorithm.transkun)
        requireSendable(TranscriptionAlgorithm.pianoTranscription)
        requireSendable(Chord.Arbiter.generic)
    }

    @Test func matchesRecordedPartitions() {
        for algorithm in Self.algorithms {
            for seed in Self.seeds {
                // without exact ties, the answer does not depend on how this machine rounds
                let indexed = Figures.indexed(Figures.jittered(Figures.notes(seed: seed), seed: seed))
                let chords = Chord.makeChords(from: indexed, optimizeFor: algorithm)
                let hash = Figures.hash(Figures.partition(chords, of: indexed))
                let key = "\(algorithm?.rawValue ?? "generic")/\(seed)"
                guard let expected = Self.recorded[key] else {
                    Issue.record("record: \"\(key)\": (\(chords.count), 0x\(String(hash, radix: 16))),")
                    continue
                }
                #expect(chords.count == expected.chords, "\(key)")
                #expect(hash == expected.hash, "\(key)")
                withExtendedLifetime(indexed) {}
            }
        }
    }

    @Test func specSelectsTheAlgorithm() {
        #expect(Chord.Spec().duration == 0.1)
        #expect(Chord.Spec(duration: 0.2).duration == 0.2)
        #expect(Chord.Spec() == Chord.Spec())
        #expect(Chord.Spec(duration: 0.1) == Chord.Spec(duration: 0.1))
        #expect(Chord.Spec() != Chord.Spec(duration: 0.1), "an explicit window is not the automatic choice, even at the same length")
        #expect(Set([Chord.Spec(), Chord.Spec(duration: 0.1), Chord.Spec(duration: 0.1)]).count == 2)
    }

    @Test(arguments: algorithms)
    func anExplicitWindowIgnoresTheTranscriptionAlgorithm(algorithm: TranscriptionAlgorithm?) {
        // 45 ms apart, a fifth: an isolated pair like this is a chord for the arbiter
        let pair = [Figures.note(0, 60, duration: 0.5), Figures.note(0.09, 67, duration: 0.5)]
        #expect(Figures.sizes(pair, optimizeFor: algorithm, spec: .init(duration: 0.1)) == [2])
        #expect(Figures.sizes(pair, optimizeFor: algorithm, spec: .init(duration: 0.05)) == [1, 1])
        #expect(Figures.sizes(pair, optimizeFor: algorithm) == [2])
    }

    @Test func explicitWindowIsTheLegacyDefault() {
        for seed in Self.seeds {
            let indexed = Figures.indexed(Figures.notes(seed: seed))
            let legacy = Figures.hash(Figures.partition(Chord.makeChords(from: indexed, spec: .init(duration: 0.1)), of: indexed))
            let transkun = Figures.hash(Figures.partition(Chord.makeChords(from: indexed, spec: .init(duration: 0.1), optimizeFor: .transkun), of: indexed))
            #expect(legacy == transkun, "seed \(seed)")
            withExtendedLifetime(indexed) {}
        }
    }

    @Test func initializerPicksThePreset() {
        #expect(Chord.Arbiter(optimizingFor: nil) == .generic)
        #expect(Chord.Arbiter(optimizingFor: .transkun) == .transkun)
        #expect(Chord.Arbiter(optimizingFor: .pianoTranscription) == .pianoTranscription)
        #expect(Set([Chord.Arbiter.generic, .transkun, .pianoTranscription]).count == 3)

        // what each may rely on
        #expect(Chord.Arbiter.generic.releaseWeight == 0, "the generic arbiter cannot trust offsets")
        #expect(Chord.Arbiter.pianoTranscription.releaseWeight == 0, "PianoTranscription's offsets cannot be relied on")
        #expect(Chord.Arbiter.transkun.releaseWeight > 0)
        #expect(Chord.Arbiter.generic.velocityWeight == 0, "an unknown transcriber may report any velocity")
        #expect(Chord.Arbiter.transkun.velocityWeight == 0)
        #expect(Chord.Arbiter.pianoTranscription.velocityWeight > 0)
    }


    // MARK: - Figures

    @Test(arguments: algorithms)
    func tinyContainers(algorithm: TranscriptionAlgorithm?) {
        let empty = MIDIContainer().indexed()
        #expect(Chord.makeChords(from: empty, optimizeFor: algorithm).isEmpty)

        let single = Figures.indexed([Figures.note(3, 60, duration: 1)])
        let chords = Chord.makeChords(from: single, optimizeFor: algorithm)
        #expect(chords.count == 1)
        #expect(chords.first?.count == 1)
        #expect(chords.first?.maxOffset == nil)
        #expect(chords.first?.features.isEmpty == true)
        withExtendedLifetime(single) {}

        // equal onsets
        #expect(Figures.sizes([Figures.note(1, 60, duration: 1), Figures.note(1, 64, duration: 1)], optimizeFor: algorithm) == [2])
        // one key twice, a beat apart
        let repeated = Figures.indexed([Figures.note(0, 60, duration: 0.5), Figures.note(1, 60, duration: 0.5)])
        #expect(Chord.makeChords(from: repeated, optimizeFor: algorithm).map(\.maxOffset) == [1, nil])
        withExtendedLifetime(repeated) {}
    }

    @Test(arguments: algorithms)
    func notesStruckTogetherAreOneChord(algorithm: TranscriptionAlgorithm?) {
        // a triad
        #expect(Figures.sizes(Figures.framed([60, 64, 67].map { Figures.note(1, $0, duration: 0.5) }), optimizeFor: algorithm) == [1, 3, 1])
        // spread by 15 ms, the way the downbeat tests play one
        #expect(Figures.sizes(Figures.framed([Figures.note(1, 60, duration: 0.5), Figures.note(1, 64, duration: 0.5), Figures.note(1.03, 67, duration: 0.5)]), optimizeFor: algorithm) == [1, 3, 1])
        // an octave doubling 50 ms apart, as played in the downbeat tests
        #expect(Figures.sizes([Figures.note(15.9, 36, duration: 0.9), Figures.note(16.0, 48, duration: 1.4)], optimizeFor: algorithm) == [2])
        // a rolled octave
        #expect(Figures.sizes(Figures.framed([Figures.note(1, 36, duration: 0.5), Figures.note(1.06, 48, duration: 0.5)]), optimizeFor: algorithm) == [1, 2, 1])
    }

    @Test(arguments: algorithms)
    func notesFarApartAreSeparateChords(algorithm: TranscriptionAlgorithm?) {
        #expect(Figures.sizes([Figures.note(0, 60, duration: 0.5), Figures.note(0.4, 64, duration: 0.5)], optimizeFor: algorithm) == [1, 1])
        #expect(Figures.sizes([Figures.note(0, 60, duration: 0.5), Figures.note(2, 64, duration: 0.5)], optimizeFor: algorithm) == [1, 1])
    }

    @Test(arguments: algorithms)
    func aSlowRunIsNotAChord(algorithm: TranscriptionAlgorithm?) {
        // a scale of eight notes, 60 ms apart: neighbors a tone or a semitone apart are successive notes
        let keys = [60, 62, 64, 65, 67, 69, 71, 72]
        let scale = keys.enumerated().map { Figures.note(1 + Double($0.offset) * 0.12, $0.element, duration: 0.08) }
        #expect(Figures.sizes(Figures.framed(scale), optimizeFor: algorithm) == Array(repeating: 1, count: 10))
        #expect(Figures.sizes(Figures.framed(scale.reversed().enumerated().map { Figures.note(1 + Double($0.offset) * 0.12, Int($0.element.note), duration: 0.08) }), optimizeFor: algorithm) == Array(repeating: 1, count: 10))
    }

    @Test(arguments: algorithms)
    func aPairStandingApartIsAChordButNotInsideAStream(algorithm: TranscriptionAlgorithm?) {
        // a fifth, 48 ms apart, with 400 ms of silence around
        let pair = [Figures.note(1, 60, duration: 0.05), Figures.note(1.096, 67, duration: 0.05)]
        #expect(Figures.sizes(Figures.framed(pair), optimizeFor: algorithm) == [1, 2, 1])

        // the same distance between all the notes of a stream
        let stream = Figures.stream(count: 40, spacingMs: 48)
        let sizes = Figures.sizes(Figures.framed(stream.map { Figures.note($0.onset + 1, Int($0.note), duration: $0.duration) }), optimizeFor: algorithm)
        // the notes at the two ends of a stream have silence on one side, and are judged like a pair standing apart
        #expect(sizes.dropFirst(4).dropLast(4).allSatisfy { $0 == 1 }, "\(sizes)")
        #expect(sizes.reduce(0, +) == 42)
    }

    @Test(arguments: algorithms)
    func aRepeatedKeyCutsTheChord(algorithm: TranscriptionAlgorithm?) {
        let indexed = Figures.indexed([
            Figures.note(1, 60, duration: 0.02),
            Figures.note(1.02, 64, duration: 0.5),
            Figures.note(1.04, 60, duration: 0.5),
        ])
        let chords = Chord.makeChords(from: indexed, optimizeFor: algorithm)
        // cut at the weakest pair between the two strikes: the second pair has the longer silence after it, so it is the stronger
        #expect(Figures.partition(chords, of: indexed) == [[0, 1], [2]])
        #expect(chords.map(\.maxOffset) == [1.04, nil])
        withExtendedLifetime(indexed) {}
    }

    @Test(arguments: algorithms)
    func aChordHoldsAtMostTwentyFourNotes(algorithm: TranscriptionAlgorithm?) {
        func simultaneous(_ count: Int) -> [Int] {
            Figures.sizes((0 ..< count).map { Figures.note(1, 30 + $0, duration: 0.5) }, optimizeFor: algorithm)
        }
        #expect(simultaneous(24) == [24])
        #expect(simultaneous(25) == [24, 1])
        #expect(simultaneous(40) == [24, 16])
        #expect(simultaneous(60) == [24, 24, 12])
    }

    @Test(arguments: algorithms)
    func aGlissandoIsNeverMerged(algorithm: TranscriptionAlgorithm?) {
        /// The size of every chord and whether it carries the glissando flag. (Chords point into the container, so only plain values leave this function.)
        func run(_ count: Int, step: Int, spacing: Double = 0.01, duration: Double = 0.1) -> [(size: Int, glissando: Bool)] {
            let indexed = Figures.indexed((0 ..< count).map { Figures.note(1 + Double($0) * spacing, 60 + $0 * step, duration: duration) })
            defer { withExtendedLifetime(indexed) {} }
            return Chord.makeChords(from: indexed, optimizeFor: algorithm).map { ($0.count, $0.features.contains(.glissando)) }
        }

        // 10 notes 5 ms apart are a chord, 11 are a glissando
        for step in [1, -1, 2] {
            let ten = run(10, step: step)
            #expect(ten.map(\.size) == [10], "step \(step)")
            #expect(ten.allSatisfy { !$0.glissando }, "step \(step)")

            let eleven = run(11, step: step)
            #expect(eleven.count == 11, "step \(step)")
            #expect(eleven.allSatisfy { $0.size == 1 && $0.glissando }, "step \(step)")
        }
        // notes of 0.2 beat or longer are not part of a glissando
        #expect(run(12, step: 1, duration: 0.2).map(\.size) == [12])
    }


    // MARK: - What each algorithm may rely on

    @Test func theReleaseOfTheFirstNoteCountsForTranskunOnly() {
        /// Whether an isolated pair of unrelated keys is one chord: the first note either held past the second's onset or released long before.
        func merged(gapMs: Double, held: Bool, _ algorithm: TranscriptionAlgorithm?) -> Bool {
            let gap = gapMs / 500
            let pair = [Figures.note(1, 60, duration: held ? gap + 0.2 : 0.02), Figures.note(1 + gap, 67, duration: 0.5)]
            return Figures.sizes(Figures.framed(pair), optimizeFor: algorithm).contains(2)
        }

        var releaseDecides = 0
        for gapMs in stride(from: 20.0, through: 160.0, by: 1.0) {
            // the generic arbiter cannot trust offsets: they are pedal-extended for most transcribers
            #expect(merged(gapMs: gapMs, held: true, nil) == merged(gapMs: gapMs, held: false, nil), "generic, \(gapMs) ms")
            // nor can PianoTranscription's, which include the ring of the sound
            #expect(merged(gapMs: gapMs, held: true, .pianoTranscription) == merged(gapMs: gapMs, held: false, .pianoTranscription), "pianoTranscription, \(gapMs) ms")
            // a released key never makes a chord likelier than a held one
            let held = merged(gapMs: gapMs, held: true, .transkun)
            let released = merged(gapMs: gapMs, held: false, .transkun)
            #expect(held || !released, "transkun, \(gapMs) ms")
            if held && !released { releaseDecides += 1 }
        }
        #expect(releaseDecides > 0, "no gap exists at which the release decides")
    }

    @Test func onlyTranskunLooksAtOffsets() {
        // the same notes with their lengths drawn again, from an instant to several seconds
        var changed = Set<String>()
        for seed in Self.seeds {
            let (original, rewritten) = Figures.withOtherOffsets(Figures.distinctNotes(seed: seed), seed: seed)
            let before = Figures.indexed(original)
            let after = Figures.indexed(rewritten)
            for algorithm in Self.algorithms {
                let same = Figures.partition(Chord.makeChords(from: before, optimizeFor: algorithm), of: before)
                    == Figures.partition(Chord.makeChords(from: after, optimizeFor: algorithm), of: after)
                if !same { changed.insert(algorithm?.rawValue ?? "generic") }
            }
            withExtendedLifetime((before, after)) {}
        }
        #expect(!changed.contains("generic"), "the generic arbiter cannot trust offsets")
        #expect(!changed.contains("pianoTranscription"), "PianoTranscription's offsets cannot be relied on")
        #expect(changed.contains("transkun"), "transkun is the one that reads offsets, so this test would notice if the others did")
    }

    @Test func theVelocityOfTheSecondNoteCountsForPianoTranscriptionOnly() {
        /// Whether an isolated pair of unrelated keys is one chord.
        func merged(gapMs: Double, first: Int = 80, second: Int, _ algorithm: TranscriptionAlgorithm?) -> Bool {
            let pair = [Figures.note(1, 60, duration: 0.5, velocity: first), Figures.note(1 + gapMs / 500, 67, duration: 0.5, velocity: second)]
            return Figures.sizes(Figures.framed(pair), optimizeFor: algorithm).contains(2)
        }

        var velocityDecides = 0
        for gapMs in stride(from: 20.0, through: 220.0, by: 1.0) {
            // an unknown transcriber may report any velocity, and transkun's cues do not include it
            for algorithm in [nil, .transkun] as [TranscriptionAlgorithm?] {
                #expect(merged(gapMs: gapMs, second: 20, algorithm) == merged(gapMs: gapMs, second: 110, algorithm), "\(algorithm?.rawValue ?? "generic"), \(gapMs) ms")
            }

            let quiet = merged(gapMs: gapMs, second: 20, .pianoTranscription)
            let loud = merged(gapMs: gapMs, second: 110, .pianoTranscription)
            #expect(quiet || !loud, "a quiet second note never makes a chord less likely, \(gapMs) ms")
            if quiet && !loud { velocityDecides += 1 }

            // only the second note counts, from 64 up nothing counts, and the cue stops growing at 24
            #expect(merged(gapMs: gapMs, first: 20, second: 110, .pianoTranscription) == loud, "\(gapMs) ms")
            #expect(merged(gapMs: gapMs, second: 64, .pianoTranscription) == loud, "\(gapMs) ms")
            #expect(merged(gapMs: gapMs, second: 24, .pianoTranscription) == merged(gapMs: gapMs, second: 1, .pianoTranscription), "\(gapMs) ms")
        }
        #expect(velocityDecides > 0, "no gap exists at which the velocity decides")
    }

    @Test(arguments: algorithms)
    func onlyTheGapsMatterNotTheAbsoluteTime(algorithm: TranscriptionAlgorithm?) {
        // transkun's grid is 23 ms, but where the grid starts is not known: only gaps may be used
        for seed in Self.seeds {
            // exactly equal gaps would tie, and a rounding error in a shifted onset would decide
            let notes = Figures.jittered(Figures.notes(seed: seed), seed: seed)
            for shift in [4.0, 1.7, 123.456] {
                let shifted = notes.map { MIDINote(onset: $0.onset + shift, offset: $0.offset + shift, note: $0.note, velocity: $0.velocity) }
                let before = Figures.indexed(notes)
                let after = Figures.indexed(shifted)
                #expect(
                    Figures.partition(Chord.makeChords(from: before, optimizeFor: algorithm), of: before)
                    == Figures.partition(Chord.makeChords(from: after, optimizeFor: algorithm), of: after),
                    "seed \(seed), shift \(shift)"
                )
                withExtendedLifetime((before, after)) {}
            }
        }
    }

    @Test(arguments: algorithms)
    func theOrderTheNotesWereGivenInDoesNotMatter(algorithm: TranscriptionAlgorithm?) {
        for seed in Self.seeds {
            let notes = Figures.notes(seed: seed)
            var rng = ChordTestRNG(seed: seed &+ 77)
            var shuffled = notes
            for index in shuffled.indices.dropLast() { shuffled.swapAt(index, index + rng.int(0 ... (shuffled.count - 1 - index))) }

            let original = Figures.indexed(notes)
            let other = Figures.indexed(shuffled)
            #expect(
                Figures.partition(Chord.makeChords(from: original, optimizeFor: algorithm), of: original)
                == Figures.partition(Chord.makeChords(from: other, optimizeFor: algorithm), of: other),
                "seed \(seed)"
            )
            withExtendedLifetime((original, other)) {}
        }
    }

    @Test func withNeutralParametersTheArbiterIsAConstantWindow() {
        for limit in [12.5, 25, 50, 100] {
            let neutral = Chord.Arbiter(
                stepLimit: limit, octaveLimit: limit, otherLimit: limit,
                previousWeight: 0, nextWeight: 0, isolationKnee: 2, isolationCap: 8, isolationFloor: 0,
                densityWeight: 0, densityCenter: 4, densityWindow: 150,
                releaseWeight: 0, releaseScale: 15, releaseCap: 3,
                maximumSize: .max
            )
            for seed in Self.seeds {
                let indexed = Figures.indexed(Figures.distinctNotes(seed: seed))
                let ordered = Figures.orderedNotes(of: indexed)
                var expected: [[Int]] = [[0]]
                for index in 1 ..< ordered.count {
                    if ordered[index].onset - ordered[index - 1].onset <= limit / 500 {
                        expected[expected.count - 1].append(index)
                    } else {
                        expected.append([index])
                    }
                }
                #expect(Figures.partition(neutral.makeChords(from: indexed), of: indexed) == expected, "\(limit) ms, seed \(seed)")
                withExtendedLifetime(indexed) {}
            }
        }
    }


    // MARK: - Invariants

    /// The properties every chord list must have, whatever the notes are.
    private func checkInvariants(_ indexed: IndexedContainer, optimizeFor algorithm: TranscriptionAlgorithm?, spec: Chord.Spec = Chord.Spec(), sizeLimit: Int? = nil, _ label: String) {
        let chords = Chord.makeChords(from: indexed, spec: spec, optimizeFor: algorithm)
        let ordered = Figures.orderedNotes(of: indexed)

        // every note is in exactly one chord
        #expect(chords.reduce(0) { $0 + $1.count } == indexed.count, "\(label)")
        var seen = Set<ReferenceNote>()
        for chord in chords {
            #expect(!chord.isEmpty, "\(label)")
            #expect(chord.allSatisfy { seen.insert($0).inserted }, "\(label): a note is in two chords")

            // no key twice
            #expect(Set(chord.map(\.note)).count == chord.count, "\(label): a key is in a chord twice")
            // sorted by onset
            #expect(zip(chord.contents, chord.contents.dropFirst()).allSatisfy { $0.onset <= $1.onset }, "\(label): contents are not sorted")
            if let sizeLimit { #expect(chord.count <= sizeLimit, "\(label): \(chord.count) notes") }

            // the earliest next onset of the members' keys comes after all members
            #expect(chord.maxOffset == Figures.expectedMaxOffset(of: chord, in: indexed), "\(label)")
            #expect(chord.maxOffset.map { limit in chord.allSatisfy { $0.onset < limit } } ?? true, "\(label)")

            // a note of a glissando is alone
            if chord.features.contains(.glissando) { #expect(chord.count == 1, "\(label)") }
        }
        #expect(seen.count == ordered.count, "\(label)")
        #expect(zip(chords, chords.dropFirst()).allSatisfy { $0.leadingOnset <= $1.leadingOnset }, "\(label): chords are not sorted")
    }

    @Test(arguments: algorithms)
    func invariantsHoldOnRandomMusic(algorithm: TranscriptionAlgorithm?) {
        for seed in 1 ... 40 {
            let indexed = Figures.indexed(Figures.notes(seed: UInt64(seed), events: 80))
            checkInvariants(indexed, optimizeFor: algorithm, sizeLimit: 24, "seed \(seed)")
            withExtendedLifetime(indexed) {}
        }
        for seed in 1 ... 10 {
            let indexed = Figures.indexed(Figures.distinctNotes(seed: UInt64(seed)))
            checkInvariants(indexed, optimizeFor: algorithm, sizeLimit: 24, "distinct \(seed)")
            withExtendedLifetime(indexed) {}
        }
    }

    @Test(arguments: algorithms)
    func invariantsHoldOnExtremeContainers(algorithm: TranscriptionAlgorithm?) {
        // 40 notes at the same instant
        let simultaneous = Figures.indexed((0 ..< 40).map { Figures.note(2, 40 + $0, duration: 0.5) })
        checkInvariants(simultaneous, optimizeFor: algorithm, sizeLimit: 24, "simultaneous")

        // every key at the same instant
        let all = Figures.indexed((21 ... 108).map { Figures.note(2, $0, duration: 0.5) })
        checkInvariants(all, optimizeFor: algorithm, sizeLimit: 24, "all keys")

        // a large piece
        let large = Figures.indexed(Figures.notes(seed: 99, events: 900))
        #expect(large.count > 3000)
        checkInvariants(large, optimizeFor: algorithm, sizeLimit: 24, "large")

        // one key struck over and over, 20 ms apart
        let repeated = Figures.indexed((0 ..< 200).map { Figures.note(Double($0) * 0.04, 60, duration: 0.02) })
        checkInvariants(repeated, optimizeFor: algorithm, sizeLimit: 1, "one key")

        // notes with a duration of zero
        let instant = Figures.indexed((0 ..< 30).map { Figures.note(Double($0) * 0.05, 50 + $0 % 7, duration: 0) })
        checkInvariants(instant, optimizeFor: algorithm, sizeLimit: 24, "instant")

        withExtendedLifetime((simultaneous, all, large, repeated, instant)) {}
    }

    @Test(arguments: algorithms)
    func theAnswerDoesNotChangeBetweenCalls(algorithm: TranscriptionAlgorithm?) {
        for seed in Self.seeds {
            let indexed = Figures.indexed(Figures.notes(seed: seed))
            let first = Figures.partition(Chord.makeChords(from: indexed, optimizeFor: algorithm), of: indexed)
            for _ in 0 ..< 3 {
                #expect(Figures.partition(Chord.makeChords(from: indexed, optimizeFor: algorithm), of: indexed) == first, "seed \(seed)")
            }
            withExtendedLifetime(indexed) {}
        }
    }

    @Test(arguments: algorithms)
    func chordsCanBeBuiltOnManyThreads(algorithm: TranscriptionAlgorithm?) async {
        let reference = Figures.notes(seed: 5)
        let expected: UInt64 = {
            let indexed = Figures.indexed(reference)
            defer { withExtendedLifetime(indexed) {} }
            return Figures.hash(Figures.partition(Chord.makeChords(from: indexed, optimizeFor: algorithm), of: indexed))
        }()
        let hashes = await withTaskGroup(of: UInt64.self) { group in
            for _ in 0 ..< 16 {
                group.addTask {
                    let indexed = Figures.indexed(reference)
                    defer { withExtendedLifetime(indexed) {} }
                    return Figures.hash(Figures.partition(Chord.makeChords(from: indexed, optimizeFor: algorithm), of: indexed))
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(hashes.allSatisfy { $0 == expected })
    }

}


/// `optimizeFor` reaches the chord algorithm from every function that takes it.
///
/// Each test builds pairs of notes at a gap where the generic arbiter and the arbiter that is being tested disagree about most pairs, found by search so that a retune does not break it, and then checks the result of the function against what the chords of its own algorithm imply.
@Suite("Chord.Arbiter forwarding")
struct ChordAlgorithmForwardingTests {

    static let algorithms: [TranscriptionAlgorithm?] = ChordArbiterTests.algorithms
    static let pairCount = 24

    typealias Figures = ChordFigures

    enum Figure {
        /// A fifth, the first note held 125 ms. A pair 100 ms apart or so is a chord for the generic arbiter and two chords for transkun.
        case held
        /// A semitone, the first note released at once.
        case semitone
    }


    /// The algorithm that the figures of a test are built to tell from the generic one: the algorithm itself, and transkun when the algorithm is the generic one.
    static func rival(of algorithm: TranscriptionAlgorithm?) -> TranscriptionAlgorithm {
        algorithm ?? .transkun
    }

    /// The notes of a figure.
    ///
    /// PianoTranscription counts a quiet second note, so the figures built to tell it from the generic arbiter have one: a pair 125 ms apart or so is then two chords for the generic arbiter and a chord for PianoTranscription. The other algorithms ignore velocity, and keep the notes they were designed with.
    static func notes(_ figure: Figure, gap: Double, rival: TranscriptionAlgorithm) -> [MIDINote] {
        let velocity = rival == .pianoTranscription ? 24 : 80
        switch figure {
        case .held:
            return Figures.framed(Figures.pairs(count: pairCount, low: 60, high: 67, gap: gap, firstDuration: 0.25, secondVelocity: velocity))
        case .semitone:
            return Figures.framed(Figures.pairs(count: pairCount, low: 66, high: 67, gap: gap, firstDuration: 0.02, secondVelocity: velocity))
        }
    }

    /// The notes of `figure` at the median of the gaps where the generic arbiter and `algorithm` (transkun for the generic arbiter itself) disagree about at least three quarters of the pairs.
    ///
    /// - Parameter oneKeepsEveryPair: Also requires that one of the arbiters does not cut a single pair apart, which a function that counts any cut needs to tell the two apart.
    static func contested(for algorithm: TranscriptionAlgorithm?, _ figure: Figure, oneKeepsEveryPair: Bool = false) -> (notes: [MIDINote], gap: Double) {
        let rival = Self.rival(of: algorithm)
        let gaps = stride(from: 0.02, through: 0.4, by: 0.002).filter { gap in
            let notes = Self.notes(figure, gap: gap, rival: rival)
            let generic = Figures.chordCount(notes, optimizeFor: nil)
            let other = Figures.chordCount(notes, optimizeFor: rival)
            return abs(generic - other) >= pairCount * 3 / 4 && (!oneKeepsEveryPair || Swift.min(generic, other) == pairCount + 2)
        }
        #expect(!gaps.isEmpty, "there is no gap at which the generic arbiter and \(rival) disagree")
        let gap = gaps.isEmpty ? 0.2 : gaps[gaps.count / 2]
        return (Self.notes(figure, gap: gap, rival: rival), gap)
    }

    /// Whether the algorithm cuts most of the pairs apart.
    static func splits(_ notes: [MIDINote], _ algorithm: TranscriptionAlgorithm?) -> Bool {
        Figures.chordCount(notes, optimizeFor: algorithm) > pairCount * 3 / 2 + 2
    }


    @Test(arguments: TranscriptionAlgorithm.allCases)
    func theAlgorithmDisagreesWithTheGenericOneOnTheFigures(algorithm: TranscriptionAlgorithm) {
        let notes = Self.contested(for: algorithm, .held).notes
        #expect(Self.splits(notes, nil) != Self.splits(notes, algorithm))

        let semitones = Self.contested(for: algorithm, .semitone, oneKeepsEveryPair: true).notes
        #expect(Self.splits(semitones, nil) != Self.splits(semitones, algorithm))
    }

    @Test(arguments: algorithms)
    func chordFunctionsForwardTheAlgorithm(algorithm: TranscriptionAlgorithm?) {
        let notes = Self.contested(for: algorithm, .held).notes
        let indexed = Figures.indexed(notes)
        defer { withExtendedLifetime(indexed) {} }

        let expected = Chord.makeChords(from: indexed, optimizeFor: algorithm).count
        #expect(expected == Figures.chordCount(notes, optimizeFor: algorithm))
        #expect(indexed.chords(optimizeFor: algorithm).count == expected)
        // nothing here is wide enough to be split between the hands
        #expect(Chord.makeSingleHandedChords(from: indexed, optimizeFor: algorithm).count == expected)

        // not passing the argument is passing `nil`
        #expect(indexed.chords().count == Chord.makeChords(from: indexed, optimizeFor: nil).count)
        #expect(Chord.makeSingleHandedChords(from: indexed).count == Chord.makeSingleHandedChords(from: indexed, optimizeFor: nil).count)
    }

    @Test(arguments: algorithms)
    func velocityProviderForwardsTheAlgorithm(algorithm: TranscriptionAlgorithm?) {
        let notes = Self.contested(for: algorithm, .held).notes
        let indexed = Figures.indexed(notes)
        defer { withExtendedLifetime(indexed) {} }

        // one point per chord
        #expect(indexed.makeVelocityProvider(optimizeFor: algorithm).single.count == Figures.chordCount(notes, optimizeFor: algorithm))
        #expect(indexed.makeVelocityProvider().single.count == Figures.chordCount(notes, optimizeFor: nil))
    }

    @Test(arguments: algorithms)
    func keySignatureForwardsTheAlgorithm(algorithm: TranscriptionAlgorithm?) {
        let notes = Self.contested(for: algorithm, .semitone, oneKeepsEveryPair: true).notes
        let indexed = Figures.indexed(notes)
        defer { withExtendedLifetime(indexed) {} }

        // F# and G, a semitone, are a motion from one chord to the next only when they are two chords
        func expected(_ algorithm: TranscriptionAlgorithm?) -> IndexedContainer.KeySignature {
            Figures.chordCount(notes, optimizeFor: algorithm) == Self.pairCount + 2 ? .natural : .sharps1
        }
        #expect(indexed.keySignature(optimizeFor: algorithm) == expected(algorithm))
        #expect(indexed.keySignature() == expected(nil))
    }

    @Test func downbeatsForwardTheAlgorithm() {
        // The bars are found from the chords, so algorithms that form other chords somewhere find other bars somewhere. Whether a figure of a few pairs moves a bar depends on loudness and timing in ways that are not worth designing around, so the music is random.
        func bars(_ algorithm: TranscriptionAlgorithm?) -> [[Double]] {
            (1 ... 10).map { seed in
                let indexed = Figures.indexed(Figures.notes(seed: UInt64(seed), events: 80))
                defer { withExtendedLifetime(indexed) {} }
                return indexed.downbeats(optimizeFor: algorithm)
            }
        }

        let results = Dictionary(uniqueKeysWithValues: Self.algorithms.map { ($0?.rawValue ?? "generic", bars($0)) })
        let names = results.keys.sorted()
        for (index, first) in names.enumerated() {
            for second in names[(index + 1)...] {
                #expect(results[first] != results[second], "\(first) and \(second) find the same bars on all ten pieces")
            }
        }

        // not passing the argument is passing `nil`
        #expect((1 ... 10).map { seed in
            let indexed = Figures.indexed(Figures.notes(seed: UInt64(seed), events: 80))
            defer { withExtendedLifetime(indexed) {} }
            return indexed.downbeats()
        } == results["generic"])

        // the anchors stay, whatever the algorithm
        let indexed = Figures.indexed(Figures.notes(seed: 3, events: 80))
        defer { withExtendedLifetime(indexed) {} }
        for algorithm in Self.algorithms {
            #expect(indexed.downbeats(beatsPerMeasure: 4, prior: [0, 2], optimizeFor: algorithm).starts(with: [0, 2]), "\(algorithm?.rawValue ?? "generic")")
        }
    }

    @Test(arguments: algorithms)
    func normalizeForwardsTheAlgorithm(algorithm: TranscriptionAlgorithm?) {
        let (notes, gap) = Self.contested(for: algorithm, .held)
        let indexed = Figures.indexed(notes)
        defer { withExtendedLifetime(indexed) {} }

        indexed.normalize(preserve: .notesDisplay, optimizeFor: algorithm)

        // A note is cut short at the next chord. A chord of a pair ends at the next pair, the first note of two chords ends where the second begins.
        let expected = Self.splits(notes, algorithm) ? gap : 0.25
        for key in [48, 72] as [UInt8] {
            let firsts = indexed.notes[key]!.contents.dropFirst(2).dropLast(2)
            #expect(!firsts.isEmpty)
            for note in firsts {
                #expect(abs(note.duration - expected) < 1e-9, "key \(key): \(note.duration), expected \(expected)")
            }
        }
    }

    @Test func normalizeWithoutTheArgumentIsTheGenericAlgorithm() {
        let notes = Self.contested(for: nil, .held).notes
        let implicit = Figures.indexed(notes)
        let explicit = Figures.indexed(notes)
        defer { withExtendedLifetime((implicit, explicit)) {} }

        implicit.normalize(preserve: .notesDisplay)
        explicit.normalize(preserve: .notesDisplay, optimizeFor: nil)
        #expect(Figures.orderedNotes(of: implicit).map(\.offset) == Figures.orderedNotes(of: explicit).map(\.offset))
    }

}
