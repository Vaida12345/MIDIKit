//
//  Indexed+MergingNotesInSameInterval.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-23.
//

import MIDIKit
import Intervals


extension IndexedTrack {

    /// Returns a track whose notes that fall in the same note of `reference` are merged.
    ///
    /// Use it when two transcriptions of the same recording disagree on how long a note is held: this track breaks a held note into fragments, and `reference` has it as a single note. `reference` decides which notes belong together, and this track keeps its own onsets and velocities.
    ///
    /// On each key, a note is located in `reference` by its center, `onset + duration / 2`: it is in the note of `reference` on the same key that contains its center, bounds inclusive, or in none. A note is merged into the note before it on its key, which is extended to end where it ends, when all of the following hold:
    ///
    /// - Both centers are in the same note of `reference`.
    /// - Its velocity is at most `threshold`.
    /// - Its velocity is at most the velocity of the note before it minus `difference`, or zero when `difference` is greater than that velocity.
    ///
    /// Merges chain: a note that absorbed the one after it is compared, by its own center and velocity, with the note after that. A loud note in the same note of `reference` is a new key press, and is kept.
    ///
    /// Both tracks must be on the same timeline, such as two transcriptions of the same audio, both in beats at 120 BPM. To merge against a track on another timeline, such as a score, warp one of them first; see ``warped(by:minimumConsecutiveNotesGap:)``.
    ///
    /// Sustains, channel events, meta events, raw data and the ``profile`` are kept. If either track has no notes, or no note is merged, the result is this track.
    ///
    /// This is `mergeNotesInSameInterval(in:threshold:difference:)` of MIDIKit 1.x, which mutated the container. Unlike it, this method keeps the channel and meta events, and does not trap when `difference` is greater than a velocity.
    ///
    /// - Parameters:
    ///   - reference: The track whose notes decide which notes of this track belong together.
    ///   - threshold: The velocity at or under which a note may be merged into the note before it.
    ///   - difference: How much quieter than the note before it a note must be to be merged into it.
    ///
    /// - Complexity: O(*n* + *m*) for tracks played in step, and O(*n* log *m*) at worst, where *n* is the number of notes of this track and *m* the number of notes of `reference`.
    ///
    /// ## User-facing Description:
    ///
    /// - Joins notes that were split apart into the single notes they were played as.
    public func mergingNotesInSameInterval(of reference: IndexedTrack, threshold: UInt8, difference: UInt8) -> IndexedTrack {
        guard !self.notes.isEmpty, !reference.notes.isEmpty else { return self }

        let lanes = self.lanes
        let referenceLanes = reference.lanes
        var notes = self.notes
        var isRemoved = [Bool](repeating: false, count: notes.count)
        var removedCount = 0

        var key = 21 as UInt8
        while key <= 108 {
            defer { key &+= 1 }
            let laneStart = lanes.starts[Int(key) &- 21]
            let laneEnd = lanes.starts[Int(key) &- 20]
            guard laneEnd &- laneStart > 1 else { continue }
            let referenceLane = referenceLanes[key]
            guard !referenceLane.isEmpty else { continue }

            // The centers rise along the lane, as its notes are disjoint, so each lookup starts from the last one found.
            var cursor = referenceLane.startIndex
            func locate(_ note: MIDINote) -> Int? {
                let index = referenceLane.index(at: note.onset + note.duration / 2, from: cursor)
                if let index { cursor = index }
                return index
            }

            var previous = lanes.members[laneStart]
            var previousInterval = locate(notes[previous])
            var position = laneStart &+ 1
            while position < laneEnd {
                let current = lanes.members[position]
                let currentInterval = locate(notes[current])
                let velocity = notes[current].velocity
                let previousVelocity = notes[previous].velocity
                let ceiling = previousVelocity > difference ? previousVelocity &- difference : 0

                if let currentInterval, currentInterval == previousInterval, velocity <= threshold, velocity <= ceiling {
                    notes[previous].offset = notes[current].offset
                    isRemoved[current] = true
                    removedCount &+= 1
                } else {
                    previous = current
                    previousInterval = currentInterval
                }
                position &+= 1
            }
        }

        guard removedCount > 0 else { return self }

        // Dropping notes keeps the order, and an extended note ends where a removed one did, before the next note on its key.
        let kept = [MIDINote](unsafeUninitializedCapacity: notes.count &- removedCount) { buffer, initializedCount in
            var write = 0
            var index = 0
            while index < notes.count {
                if !isRemoved[index] {
                    (buffer.baseAddress! + write).initialize(to: notes[index])
                    write &+= 1
                }
                index &+= 1
            }
            initializedCount = write
        }

        return IndexedTrack(validated: kept, sustains: self.sustains, channelEvents: self.channelEvents, metaEvents: self.metaEvents, rawData: self.rawData, profile: self.profile)
    }

}
