//
//  Indexed+Normalizing.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import MIDIKit
import Essentials


extension IndexedTrack {

    /// Returns a track whose note lengths are adjusted using the sustain pedal and nearby notes, fixing overly long notes and overlaps.
    ///
    /// The notes are grouped into ``chords`` by the ``profile``. Each note is then given an offset from where its onset and offset fall among the sustains, and from where the next chord starts:
    ///
    /// - A note that starts and ends within one sustain ends no later than the next chord.
    /// - A note that reaches into the next sustain is kept long enough to reach it.
    /// - A note that spans more sustains, or none, is left as it is to keep the acoustic result, or ends no later than the next chord to keep the notes readable, as `preserve` decides.
    ///
    /// A release up to 1/4 beat after a sustain ends counts as within it, and so does a release in a gap shorter than 1/2 beat between two sustains. A note is never shortened below 0.1 beat by these rules. The notes of the last chord keep their offsets. Finally, every note ends before the next note on its key starts.
    ///
    /// Only offsets change: onsets, sustains, channel events, meta events and the ``profile`` are kept as they are.
    ///
    /// - Parameter preserve: What to favor where the sustains do not decide: the acoustic result, or readable notes.
    ///
    /// - Complexity: O(*n* log *m*), where *n* is the number of notes and *m* the number of sustains, in addition to forming the ``chords`` on first use.
    ///
    /// ## User-facing Description:
    /// Automatically adjusts note durations using the sustain pedal and nearby notes, fixing overly long notes and overlaps for more natural playback and clearer chords.
    ///
    /// - Adjusts note lengths to fix overlaps for clearer chords.
    public func normalizing(preserve: PreserveSettings) -> IndexedTrack {
        guard !self.notes.isEmpty else { return self }

        let chords = self.chords
        let lanes = self.lanes
        let sustains = self.sustains
        var notes = self.notes

        // Each note depends only on its own original times, the next chord, and the sustains, so the order does not matter.
        var index = 0
        while index &+ 1 < chords.count {
            let chord = chords[index]
            let nextOnset = chords[index &+ 1].leadingOnset
            var position = 0
            while position < chord.count {
                let noteIndex = chord.noteIndices[position]
                notes[noteIndex].offset = Self.normalizedOffset(onset: notes[noteIndex].onset, offset: notes[noteIndex].offset, nextOnset: nextOnset, sustains: sustains, preserve: preserve)
                position &+= 1
            }
            index &+= 1
        }

        // Finally, make sure the notes on each key are disjoint.
        var key = 0
        while key < 88 {
            var position = lanes.starts[key]
            let end = lanes.starts[key &+ 1]
            while position &+ 1 < end {
                let current = lanes.members[position]
                let next = lanes.members[position &+ 1]
                notes[current].offset = Swift.min(notes[current].offset, notes[next].onset.nextDown)
                position &+= 1
            }
            key &+= 1
        }

        return IndexedTrack(validated: notes, sustains: sustains, channelEvents: self.channelEvents, metaEvents: self.metaEvents, rawData: self.rawData, profile: self.profile, reusingLayoutOf: lanes)
    }


    /// The shortest a note is made by ``normalizing(preserve:)``, in beats.
    private static let normalizingMinimumLength: Double = 0.1

    /// How long after a sustain ends a release still counts as within it, in beats.
    private static let normalizingMargin: Double = 1/4

    /// Returns the offset of a note normalized against the sustains and the onset of the next chord.
    ///
    /// - Parameters:
    ///   - onset: The onset of the note.
    ///   - offset: The original offset of the note.
    ///   - nextOnset: The leading onset of the next chord.
    ///   - sustains: The sustains of the track.
    ///   - preserve: What to favor where the sustains do not decide.
    private static func normalizedOffset(onset: Double, offset: Double, nextOnset: Double, sustains: Sustains, preserve: PreserveSettings) -> Double {
        let minimumLength = normalizingMinimumLength
        let margin = normalizingMargin

        // The naming ignores the word `sustain`: `onsetIndex` is the sustain at the onset, and so on.
        let onsetIndex = sustains.index(at: onset)
        let onsetNextIndex = sustains.firstIndex(after: onset)
        let offsetPreviousIndex = sustains.lastIndex(before: offset)
        let offsetNextIndex = sustains.firstIndex(after: offset)

        let offsetPrevious = offsetPreviousIndex.map { sustains[$0] }
        let offsetNext = offsetNextIndex.map { sustains[$0] }

        let offsetIndex: Int?
        if let region = sustains.index(at: offset) {
            offsetIndex = region
        } else if let offsetPrevious,
                  offsetPrevious.offset > offset - margin,
                  offsetNext.isNil(or: { offset < $0.onset }),
                  onset <= offsetPrevious.offset {
            // Released within the margin after a sustain: treat it as released within that sustain.
            offsetIndex = offsetPreviousIndex
        } else if let offsetPrevious, let offsetNext = sustains.first(after: offset),
                  offsetNext.onset - offsetPrevious.offset < margin * 2 {
            // The gap between the sustains is tiny: treat it as a sustain reset, within the previous sustain.
            offsetIndex = offsetPreviousIndex
        } else {
            offsetIndex = nil
        }

        /// Sets the offset, keeping the note at least `minimumLength` long.
        func noteOffset(_ value: Double) -> Double {
            Swift.max(value, onset + minimumLength)
        }

        /// The note ends without a sustain.
        func noOffsetSustain() -> Double {
            switch preserve {
            case .acousticResult: offset
            case .notesDisplay: noteOffset(clamp(offset, max: nextOnset))
            }
        }

        /// Extends the note far enough to reach `sustain`.
        func span(_ sustain: MIDISustainEvent) -> Double {
            if sustain.onset < nextOnset {
                return noteOffset(clamp(offset, min: sustain.onset + minimumLength))
            } else {
                switch preserve {
                case .acousticResult: return noteOffset(sustain.onset + minimumLength) // as short as possible
                case .notesDisplay: return noteOffset(nextOnset)
                }
            }
        }

        /// The note spans at least three sustains.
        func excessiveSpan() -> Double {
            switch preserve {
            case .acousticResult:
                return offset
            case .notesDisplay:
                // make it at least as long as to reach the next sustain
                if let onsetNextIndex {
                    return span(sustains[onsetNextIndex])
                } else {
                    return noteOffset(clamp(offset, max: nextOnset))
                }
            }
        }

        /// The note has no sustain around it.
        func noSustain() -> Double {
            switch preserve {
            case .acousticResult: offset // within the same non-sustained region, keep it as it is
            case .notesDisplay: noOffsetSustain()
            }
        }

        if let onsetIndex, let offsetIndex {
            // Sustains were found for both the onset and the offset.
            if onsetIndex == offsetIndex {
                // Within the same sustain, the length can be free: only the next chord limits it.
                return noteOffset(clamp(offset, max: nextOnset))
            } else if onsetNextIndex == offsetIndex {
                // The onset and offset are in adjacent sustains.
                return span(sustains[offsetIndex])
            } else {
                // The note spans three sustains or more.
                return excessiveSpan()
            }
        } else if let offsetIndex {
            // A sustain was found for the offset, but not the onset.
            if onsetNextIndex == offsetIndex {
                // The next sustain after the onset is the one at the offset.
                return span(sustains[offsetIndex])
            } else {
                // The note spans two sustains or more, without a leading sustain.
                return excessiveSpan()
            }
        } else if let onsetIndex {
            // A sustain was found for the onset, but not the offset.
            if let offsetPreviousIndex, offsetPreviousIndex > onsetIndex {
                // The note spans at least one more sustain.
                return span(sustains[offsetPreviousIndex])
            } else if offsetPreviousIndex == onsetIndex {
                // The note ends between this sustain and the next.
                return noOffsetSustain()
            } else {
                // The offset is after the onset's sustain ends, so `offsetPreviousIndex` is at least `onsetIndex`.
                assertionFailure("A note that starts within a sustain must end within or after it.")
                return noteOffset(clamp(offset, max: nextOnset))
            }
        } else {
            // Neither the onset nor the offset is within a sustain.
            if onsetNextIndex != nil && onsetNextIndex == offsetNextIndex {
                // No sustain within the note.
                return noSustain()
            } else if onsetNextIndex == offsetPreviousIndex {
                if let offsetPreviousIndex {
                    // The note spans one sustain.
                    return span(sustains[offsetPreviousIndex])
                } else {
                    // No sustain within the note.
                    return noSustain()
                }
            } else {
                // The note spans more than one sustain.
                return excessiveSpan()
            }
        }
    }

}
