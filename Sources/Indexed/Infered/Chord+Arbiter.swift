//
//  Chord+Arbiter.swift
//  MIDIKit
//
//  Created by Vaida on 11/9/26.
//

import Foundation


extension Chord {

    /// Forms chords by judging, for every two notes that are next to each other in time, whether they were struck together.
    ///
    /// A constant window cannot do this: two notes 40 ms apart are a chord in one place and the start of a run in another. The arbiter weighs the evidence around each pair instead.
    ///
    /// - The **gap** between the onsets. The smaller it is, the likelier a chord.
    /// - The **interval**. Neighbors a semitone or a tone apart are almost always successive notes of a run, an octave is almost always a doubling, anything else lies between. Each class has its own limit for the gap.
    /// - The **gaps around the pair**. A pair that stands apart from its neighbors is a chord more likely than the same pair inside a stream of evenly spaced notes.
    /// - The **density**. A crowded neighborhood lowers the limit, as a fast passage is rarely made of chords.
    /// - The **release** of the first note (only when the transcriber is known to report it faithfully). A key that is still down when the next one goes down says chord; a key that is already up says sequence.
    /// - The **velocity** of the second note (only when the transcriber is known to report it on the scale of a MIDI keyboard). A note that starts shortly after another and is much quieter than a typical note is, more often than not, part of its chord: an inner voice, a note struck softly. A louder note is a note of a melody.
    ///
    /// The evidence of a pair is one number, its margin: positive means the same chord. Hard constraints come afterwards. A key is never in a chord twice, a chord holds at most ``maximumSize`` notes, and a note that is part of a glissando is never merged. Where a constraint forces a cut, it falls on the pair with the smallest margin.
    ///
    /// Everything is in milliseconds, `onset * 500`, as a container is always at 120 BPM. Onsets are multiplied before they are subtracted: `16.0 * 500 - 15.9 * 500` and `(16.0 - 15.9) * 500` differ in the last bits, and the parameters were tuned with the former.
    ///
    /// - Complexity: O(n log n), where *n* is the number of notes.
    struct Arbiter: Sendable, Hashable {

        /// The gap in milliseconds, up to about which two notes whose keys are one or two semitones apart are merged. They are almost always successive notes of a run.
        var stepLimit: Double

        /// The same for an octave, which is almost always a doubling.
        var octaveLimit: Double

        /// The same for every other interval.
        var otherLimit: Double

        /// How much a gap that is large compared with the gap before the pair raises the limit, in the logarithm of the limit.
        var previousWeight: Double

        /// The same for the gap after the pair.
        var nextWeight: Double

        /// The ratio between a neighbor gap and the pair's gap from which isolation counts.
        var isolationKnee: Double

        /// The ratio from which isolation stops counting.
        var isolationCap: Double

        /// How far below the knee the isolation may go negative: a neighbor gap smaller than the pair's gap says that one of the two notes belongs to a tighter group.
        var isolationFloor: Double

        /// How much a crowded neighborhood lowers the limit, in the logarithm of the limit. Negative lowers it.
        var densityWeight: Double

        /// The number of notes within `densityWindow` of the pair's first note above which the neighborhood counts as crowded.
        var densityCenter: Double

        /// The radius in milliseconds of the neighborhood that is counted.
        var densityWindow: Double

        /// How much the release of the first note counts, in the logarithm of the limit. `0` leaves the release out, which is what an unknown transcriber needs: one that holds notes with the sustain pedal reports offsets that say nothing about the keys.
        var releaseWeight: Double

        /// The scale in milliseconds of the overlap between the first note's release and the second note's onset: the cue is `releaseWeight * ln(1 + abs(overlap) / releaseScale)`, with the sign of the overlap.
        var releaseScale: Double

        /// The largest strength of the release cue.
        var releaseCap: Double

        /// How much a quiet second note counts, in the logarithm of the limit: the cue is `velocityWeight * min(max((velocityCenter - velocity) / 10, 0), velocityCap)`, where `velocity` is the second note's. `0` leaves the velocity out, which is what an unknown transcriber needs: one that reports every note at a constant velocity of 40 would make every pair look quiet.
        var velocityWeight: Double

        /// The velocity from which the second note counts as quiet.
        var velocityCenter: Double

        /// The largest strength of the velocity cue, in tens of velocity units below `velocityCenter`.
        var velocityCap: Double

        /// A chord never holds more notes than this.
        var maximumSize: Int


        /// What nothing is known about the transcriber: it relies on neither the timing grid nor the offsets.
        ///
        /// Tuned on the transcription of the MAESTRO dataset, the exact recordings and a perturbed version of the recordings (10 ms of onset error, notes held by the pedal).
        static let generic = Arbiter(
            stepLimit: 25,
            octaveLimit: 54.45,
            otherLimit: 44.1,
            previousWeight: 0.37,
            nextWeight: 0.21,
            isolationKnee: 2,
            isolationCap: 8,
            isolationFloor: 0.1,
            densityWeight: -0.18,
            densityCenter: 4,
            densityWindow: 150,
            releaseWeight: 0,
            releaseScale: 15,
            releaseCap: 3,
            velocityWeight: 0,
            velocityCenter: 64,
            velocityCap: 4,
            maximumSize: 24
        )

        /// [Transkun](https://github.com/Yujia-Yan/Transkun): onsets sit on a grid of about 23 ms, so a gap of two frames is the only one that is a coin flip, and the offsets follow the keys, which makes the release a usable cue.
        ///
        /// Tuned on the transcription of the MAESTRO dataset.
        static let transkun = Arbiter(
            stepLimit: 22.5,
            octaveLimit: 49.005,
            otherLimit: 39.69,
            previousWeight: 0.37,
            nextWeight: 0.14,
            isolationKnee: 2,
            isolationCap: 8,
            isolationFloor: 0.1,
            densityWeight: -0.18,
            densityCenter: 4,
            densityWindow: 150,
            releaseWeight: 0.1,
            releaseScale: 14.7,
            releaseCap: 3,
            velocityWeight: 0,
            velocityCenter: 64,
            velocityCap: 4,
            maximumSize: 24
        )

        /// PianoTranscription: the offsets cannot be relied on (they include the ring of the sound), so the release is left out, and the timing has no grid that helps. What it adds to the generic arbiter is the velocity of the second note, which this transcriber reports on the scale of a MIDI keyboard.
        ///
        /// Tuned on the transcription of the MAESTRO dataset. The constants of the generic arbiter were already right for this input: retuning them gained 0.03 of the tuning objective, and not in every fold. The velocity cue gained 0.23 (more chords found exactly, fewer gray-zone pairs wrong), in all four folds. A weak grid model, a cap on the span of a chord and a constraint on runs gained nothing.
        static let pianoTranscription = Arbiter(
            stepLimit: 25,
            octaveLimit: 54.45,
            otherLimit: 44.1,
            previousWeight: 0.37,
            nextWeight: 0.21,
            isolationKnee: 2,
            isolationCap: 8,
            isolationFloor: 0.1,
            densityWeight: -0.18,
            densityCenter: 4,
            densityWindow: 150,
            releaseWeight: 0,
            releaseScale: 15,
            releaseCap: 3,
            velocityWeight: 0.1,
            velocityCenter: 64,
            velocityCap: 4,
            maximumSize: 24
        )

        /// The arbiter for notes that `transcriptionAlgorithm` produced, or the generic one when it is unknown.
        init(optimizingFor transcriptionAlgorithm: TranscriptionAlgorithm?) {
            switch transcriptionAlgorithm {
            case nil:
                self = .generic
            case .transkun:
                self = .transkun
            case .pianoTranscription:
                self = .pianoTranscription
            }
        }

        init(
            stepLimit: Double,
            octaveLimit: Double,
            otherLimit: Double,
            previousWeight: Double,
            nextWeight: Double,
            isolationKnee: Double,
            isolationCap: Double,
            isolationFloor: Double,
            densityWeight: Double,
            densityCenter: Double,
            densityWindow: Double,
            releaseWeight: Double,
            releaseScale: Double,
            releaseCap: Double,
            velocityWeight: Double = 0,
            velocityCenter: Double = 64,
            velocityCap: Double = 4,
            maximumSize: Int
        ) {
            self.stepLimit = stepLimit
            self.octaveLimit = octaveLimit
            self.otherLimit = otherLimit
            self.previousWeight = previousWeight
            self.nextWeight = nextWeight
            self.isolationKnee = isolationKnee
            self.isolationCap = isolationCap
            self.isolationFloor = isolationFloor
            self.densityWeight = densityWeight
            self.densityCenter = densityCenter
            self.densityWindow = densityWindow
            self.releaseWeight = releaseWeight
            self.releaseScale = releaseScale
            self.releaseCap = releaseCap
            self.velocityWeight = velocityWeight
            self.velocityCenter = velocityCenter
            self.velocityCap = velocityCap
            self.maximumSize = maximumSize
        }


        /// A note, in the units the arbiter works with.
        private struct Entry {

            let reference: ReferenceNote

            let key: UInt8

            /// Milliseconds, `onset * 500`.
            let onset: Double

            /// Milliseconds, `offset * 500`.
            let offset: Double

            /// The MIDI velocity.
            let velocity: Double

            /// The onset in beats of the next note of the same key.
            let nextOnset: Double?

        }


        /// Groups the notes of `container` into chords.
        ///
        /// Each returned chord is non-empty, holds each key at most once, and its notes are sorted by onset. The chords are sorted by their leading onset.
        ///
        /// - Complexity: O(n log n)
        func makeChords(from container: IndexedContainer) -> [Chord] {
            guard !container.isEmpty else { return [] }

            // The notes in onset order, ties broken by the key.
            var entries: [Entry] = []
            entries.reserveCapacity(container.count)
            for key in 21 ... 108 as ClosedRange<UInt8> {
                guard let notes = container.notes[key] else { continue }
                for (index, note) in notes.contents.enumerated() {
                    entries.append(Entry(
                        reference: note,
                        key: key,
                        onset: note.onset * 500,
                        offset: note.offset * 500,
                        velocity: Double(note.velocity),
                        nextOnset: index + 1 < notes.contents.count ? notes.contents[index + 1].onset : nil
                    ))
                }
            }
            entries.sort { $0.onset != $1.onset ? $0.onset < $1.onset : $0.key < $1.key }

            let count = entries.count
            let onsets = entries.map(\.onset)

            var glissando = [Bool](repeating: false, count: count)
            for run in Chord.glissandoRuns(in: entries.map(\.reference), sustains: container.sustains) {
                for index in run {
                    glissando[index] = true
                }
            }

            let margins = self.margins(entries: entries, onsets: onsets, glissando: glissando)

            // Grow each chord from its first note while the pair at its end has a positive margin.
            var chords: [Chord] = []
            var lastSeen = [Int](repeating: -1, count: 128) // the index in `entries` at which a key was last put into the chord that is being grown
            var start = 0
            while start < count {
                var end = start
                var scanned = start // the last note that was looked at, which can be beyond `end` when a repeated key cuts the chord short
                lastSeen[Int(entries[start].key)] = start

                grow: while end + 1 < count && margins[end] > 0 && end + 1 - start < self.maximumSize {
                    let key = Int(entries[end + 1].key)
                    if lastSeen[key] >= start {
                        // A key cannot be struck twice in one chord: cut at the weakest pair between the two strikes.
                        var weakest = lastSeen[key]
                        for index in lastSeen[key] ..< end + 1 where margins[index] < margins[weakest] {
                            weakest = index
                        }
                        end = weakest
                        break grow
                    }
                    lastSeen[key] = end + 1
                    end += 1
                    scanned = end
                }

                // The next chord starts clean, including from the notes that were looked at but cut off.
                for index in start ... scanned {
                    lastSeen[Int(entries[index].key)] = -1
                }

                var maxOffset: Double?
                for index in start ... end {
                    guard let next = entries[index].nextOnset else { continue }
                    maxOffset = maxOffset.map { Swift.min($0, next) } ?? next
                }

                // A note of a glissando is never merged, so it is a chord of its own.
                chords.append(Chord(
                    contents: entries[start ... end].map(\.reference),
                    maxOffset: maxOffset,
                    features: glissando[start] ? [.glissando] : []
                ))
                start = end + 1
            }

            return chords
        }


        /// How firmly the note at each index belongs with the note after it: positive merges. The last note has no pair.
        ///
        /// A repeated key, a glissando and a gap that is not a number are `-infinity`.
        private func margins(entries: [Entry], onsets: [Double], glissando: [Bool]) -> [Double] {
            let count = entries.count
            guard count > 1 else { return [] }

            // The number of notes within the radius of each note, itself included.
            var density = [Double](repeating: 0, count: count)
            var low = 0
            var high = 0
            for index in 0 ..< count {
                while onsets[index] - onsets[low] > self.densityWindow { low += 1 }
                while high + 1 < count && onsets[high + 1] - onsets[index] <= self.densityWindow { high += 1 }
                density[index] = Double(high - low + 1)
            }

            let logKnee = log(self.isolationKnee)
            let logCap = log(self.isolationCap)
            let lowest = -self.isolationFloor

            var margins = [Double](repeating: 0, count: count - 1)
            for index in 0 ..< count - 1 {
                // 0.5 ms is below what any transcription resolves: notes struck together can be a rounding error apart, or none.
                let gap = Swift.max(onsets[index + 1] - onsets[index], 0.5)
                let interval = abs(Int(entries[index + 1].key) - Int(entries[index].key))
                guard gap.isFinite, interval != 0, !glissando[index], !glissando[index + 1] else {
                    margins[index] = -.infinity
                    continue
                }

                let limit = interval <= 2 ? self.stepLimit : (interval == 12 ? self.octaveLimit : self.otherLimit)

                // A pair at the edge of the piece has silence around it, 3 s.
                let before = index > 0 ? Swift.min(Swift.max(onsets[index] - onsets[index - 1], 0.5), 3000) : 3000
                let after = index + 2 < count ? Swift.min(Swift.max(onsets[index + 2] - onsets[index + 1], 0.5), 3000) : 3000
                let isolationBefore = Swift.min(Swift.max(log(before / gap) - logKnee, lowest), logCap)
                let isolationAfter = Swift.min(Swift.max(log(after / gap) - logKnee, lowest), logCap)
                let crowd = Swift.min(Swift.max(density[index] - self.densityCenter, -2), 6) / 4
                var margin = log(limit) + self.previousWeight * isolationBefore + self.nextWeight * isolationAfter + self.densityWeight * crowd - log(gap)

                if self.releaseWeight != 0 {
                    // positive: the first note is still down when the second goes down
                    let overlap = entries[index].offset - entries[index + 1].onset
                    let magnitude = log(1 + abs(overlap) / self.releaseScale)
                    margin += self.releaseWeight * Swift.min(Swift.max(overlap < 0 ? -magnitude : magnitude, -self.releaseCap), self.releaseCap)
                }

                if self.velocityWeight != 0 {
                    // positive: the second note is quieter than the center
                    margin += self.velocityWeight * Swift.min(Swift.max((self.velocityCenter - entries[index + 1].velocity) / 10, 0), self.velocityCap)
                }

                margins[index] = margin
            }
            return margins
        }

    }

}
