//
//  EngravingReference.swift
//  MIDIKit
//

import Foundation


/// An immutable musical and layout reference for ``EngravingScoreFollower``.
///
/// Measures, system lines, and musical moments are deliberately owned by one value. Replacing
/// the reference therefore cannot leave the follower with mismatched score and layout state.
public struct EngravingReference: Sendable, Hashable {

    public enum Hand: UInt8, Sendable, Hashable, CaseIterable {
        case left
        case right
    }

    public enum Attack: UInt8, Sendable, Hashable {
        case block
        case rolled
    }

    public struct Note: Sendable, Hashable {
        public let pitch: UInt8
        public let duration: Double
        public let hand: Hand

        public init(pitch: UInt8, duration: Double, hand: Hand) {
            self.pitch = pitch
            self.duration = duration
            self.hand = hand
        }
    }

    public struct Moment: Sendable, Hashable {
        public let beat: Double
        public let notes: [Note]
        public let attack: Attack

        public init(beat: Double, notes: [Note], attack: Attack = .block) {
            self.beat = beat
            self.notes = notes
            self.attack = attack
        }
    }

    public struct Measure: Sendable, Hashable {
        public let index: Int
        public let onset: Double
        public let duration: Double

        public var beatRange: ClosedRange<Double> { onset...(onset + duration) }

        public init(index: Int, onset: Double, duration: Double) {
            self.index = index
            self.onset = onset
            self.duration = duration
        }
    }

    public struct Line: Sendable, Hashable {
        public let index: Int
        public let beatRange: ClosedRange<Double>
        public let measureRange: ClosedRange<Int>

        public init(
            index: Int,
            beatRange: ClosedRange<Double>,
            measureRange: ClosedRange<Int>
        ) {
            self.index = index
            self.beatRange = beatRange
            self.measureRange = measureRange
        }
    }

    public enum ValidationError: Error, LocalizedError, Sendable, Hashable {
        case emptyMeasures
        case emptyLines
        case emptyMoments
        case duplicateMeasureIndex(Int)
        case duplicateLineIndex(Int)
        case invalidMeasure(Int)
        case nonIncreasingMeasureIndex(Int)
        case invalidLine(Int)
        case measureWithoutLine(Int)
        case invalidMoment(Double)
        case momentOutsideMeasures(Double)
        case invalidNote(pitch: UInt8, beat: Double)

        public var errorDescription: String? {
            switch self {
            case .emptyMeasures:
                "An engraving reference must contain at least one measure."
            case .emptyLines:
                "An engraving reference must contain at least one line."
            case .emptyMoments:
                "An engraving reference must contain at least one musical moment."
            case let .duplicateMeasureIndex(index):
                "Measure index \(index) occurs more than once."
            case let .duplicateLineIndex(index):
                "Line index \(index) occurs more than once."
            case let .invalidMeasure(index):
                "Measure \(index) must have a finite onset and a finite, positive duration."
            case let .nonIncreasingMeasureIndex(index):
                "Measure index \(index) is not greater than the preceding measure index."
            case let .invalidLine(index):
                "Line \(index) has an invalid beat or measure range."
            case let .measureWithoutLine(index):
                "Measure \(index) does not belong to exactly one engraving line."
            case let .invalidMoment(beat):
                "The reference moment at beat \(beat) is empty or invalid."
            case let .momentOutsideMeasures(beat):
                "The reference moment at beat \(beat) does not belong to a measure."
            case let .invalidNote(pitch, beat):
                "Pitch \(pitch) at beat \(beat) is outside MIDI 1.0 or has an invalid duration."
            }
        }
    }

    public let measures: [Measure]
    public let lines: [Line]
    public let moments: [Moment]

    /// Creates a validated reference. Moments at the same onset are merged, and duplicate
    /// pitch/hand notes retain the longest written duration.
    public init(measures: [Measure], lines: [Line], moments: [Moment]) throws {
        guard !measures.isEmpty else { throw ValidationError.emptyMeasures }
        guard !lines.isEmpty else { throw ValidationError.emptyLines }
        guard !moments.isEmpty else { throw ValidationError.emptyMoments }

        let sortedMeasures = measures.sorted {
            $0.onset == $1.onset ? $0.index < $1.index : $0.onset < $1.onset
        }
        var measureIndices = Set<Int>(minimumCapacity: sortedMeasures.count)
        for measure in sortedMeasures {
            guard measure.onset.isFinite, measure.duration.isFinite, measure.duration > 0 else {
                throw ValidationError.invalidMeasure(measure.index)
            }
            guard measureIndices.insert(measure.index).inserted else {
                throw ValidationError.duplicateMeasureIndex(measure.index)
            }
        }
        for offset in sortedMeasures.indices.dropFirst() {
            let previous = sortedMeasures[offset - 1]
            let current = sortedMeasures[offset]
            guard current.onset >= previous.onset + previous.duration - Self.beatEpsilon else {
                throw ValidationError.invalidMeasure(current.index)
            }
            guard current.index > previous.index else {
                throw ValidationError.nonIncreasingMeasureIndex(current.index)
            }
        }

        let sortedLines = lines.sorted {
            $0.beatRange.lowerBound == $1.beatRange.lowerBound
                ? $0.index < $1.index
                : $0.beatRange.lowerBound < $1.beatRange.lowerBound
        }
        var lineIndices = Set<Int>(minimumCapacity: sortedLines.count)
        for line in sortedLines {
            guard line.beatRange.lowerBound.isFinite, line.beatRange.upperBound.isFinite,
                  line.beatRange.lowerBound <= line.beatRange.upperBound,
                  lineIndices.insert(line.index).inserted else {
                if lineIndices.contains(line.index) {
                    throw ValidationError.duplicateLineIndex(line.index)
                }
                throw ValidationError.invalidLine(line.index)
            }
            guard sortedMeasures.contains(where: { $0.index == line.measureRange.lowerBound }),
                  sortedMeasures.contains(where: { $0.index == line.measureRange.upperBound }) else {
                throw ValidationError.invalidLine(line.index)
            }
        }

        for measure in sortedMeasures {
            let containingLines = sortedLines.filter { $0.measureRange.contains(measure.index) }
            guard containingLines.count == 1 else {
                throw ValidationError.measureWithoutLine(measure.index)
            }
            guard let line = containingLines.first,
                  line.beatRange.lowerBound <= measure.onset + Self.beatEpsilon,
                  line.beatRange.upperBound + Self.beatEpsilon >= measure.onset + measure.duration else {
                throw ValidationError.invalidLine(containingLines.first?.index ?? -1)
            }
        }

        let normalizedMoments = try Self.normalize(moments)
        for moment in normalizedMoments {
            guard Self.measureOffset(containing: moment.beat, in: sortedMeasures) != nil else {
                throw ValidationError.momentOutsideMeasures(moment.beat)
            }
        }

        self.measures = sortedMeasures
        self.lines = sortedLines
        self.moments = normalizedMoments
    }

    static let beatEpsilon = 1e-6

    static func measureOffset(containing beat: Double, in measures: [Measure]) -> Int? {
        guard beat.isFinite else { return nil }
        var lower = 0
        var upper = measures.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if measures[middle].onset <= beat + beatEpsilon {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        let candidate = max(0, lower - 1)
        guard measures.indices.contains(candidate) else { return nil }
        let measure = measures[candidate]
        guard beat >= measure.onset - beatEpsilon,
              beat <= measure.onset + measure.duration + beatEpsilon else { return nil }
        return candidate
    }

    private struct NoteKey: Hashable {
        let pitch: UInt8
        let hand: Hand
    }

    private static func normalize(_ moments: [Moment]) throws -> [Moment] {
        let sorted = moments.sorted {
            $0.beat == $1.beat ? $0.notes.count < $1.notes.count : $0.beat < $1.beat
        }
        var result: [Moment] = []
        result.reserveCapacity(sorted.count)

        for moment in sorted {
            guard moment.beat.isFinite, !moment.notes.isEmpty else {
                throw ValidationError.invalidMoment(moment.beat)
            }
            for note in moment.notes {
                guard note.pitch < 128, note.duration.isFinite, note.duration >= 0 else {
                    throw ValidationError.invalidNote(pitch: note.pitch, beat: moment.beat)
                }
            }

            guard let previous = result.last,
                  abs(previous.beat - moment.beat) <= beatEpsilon else {
                result.append(Moment(
                    beat: moment.beat,
                    notes: normalizedNotes(moment.notes),
                    attack: moment.attack
                ))
                continue
            }

            result[result.count - 1] = Moment(
                beat: previous.beat,
                notes: normalizedNotes(previous.notes + moment.notes),
                attack: previous.attack == .rolled || moment.attack == .rolled ? .rolled : .block
            )
        }
        return result
    }

    private static func normalizedNotes(_ notes: [Note]) -> [Note] {
        var longest: [NoteKey: Double] = [:]
        longest.reserveCapacity(notes.count)
        for note in notes {
            let key = NoteKey(pitch: note.pitch, hand: note.hand)
            longest[key] = max(longest[key] ?? 0, note.duration)
        }
        return longest.map { Note(pitch: $0.key.pitch, duration: $0.value, hand: $0.key.hand) }
            .sorted {
                $0.pitch == $1.pitch
                    ? $0.hand.rawValue < $1.hand.rawValue
                    : $0.pitch < $1.pitch
            }
    }
}
