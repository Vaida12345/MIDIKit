//
//  IndexedTrack+Init.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import MIDIKit
import Intervals


extension IndexedTrack {
    
    /// Creates an indexed track from every track of a container, cleaned up for analysis.
    ///
    /// The container is converted to a constant 120 BPM, and the tracks are merged into one. Notes keep their original channels; which track a note came from is not kept. Then:
    ///
    /// - Notes whose pitch is outside `21...108`, whose times are not finite, or that end before they start are dropped.
    /// - Two notes on the same key whose onsets are closer than `minimumConsecutiveNotesGap` are merged into one, with the earlier onset, the later offset and the louder velocity: the later one is usually a second trigger of the same strike.
    /// - Every note ends at least `minimumConsecutiveNotesGap` before the next note on its key starts. A note that this leaves shorter than `minimumConsecutiveNotesGap` is dropped.
    /// - The sustains of every track are combined as ``MIDISustainEvents/init(_:minimumGap:)`` describes, with `minimumConsecutiveNotesGap` as the gap: invalid ones are dropped, two whose onsets are closer than the gap are merged, and every other one ends at least the gap before the next one starts, so every pedal change is kept.
    /// - Meta events are collected from every track and from the tempo track, which holds the time and key signatures of format-1 files. Raw messages, such as SysEx, are collected from every track.
    ///
    /// The ``lanes`` are built along the way, so the first access to them costs nothing.
    ///
    /// - Parameters:
    ///   - container: The source container.
    ///   - profile: The choices the analyses of this track make.
    ///   - minimumConsecutiveNotesGap: The minimum gap between consecutive notes on the same key, in beats at 120 BPM. It must be finite and greater than zero. The default value is `1/128`.
    ///
    /// - Complexity: O(*n* log *n*), where *n* is the number of notes.
    public init(_ container: MIDIContainer, profile: some AnalysisProfile = .generic, minimumConsecutiveNotesGap: Double = 1/128) {
        let gap = minimumConsecutiveNotesGap
        precondition(gap.isFinite && gap > 0, "minimumConsecutiveNotesGap must be finite and greater than zero")
        
        var source = container
        source.normalizeToConstantTempo(120)
        let tracks = source.tracks
        
        // MARK: Collect valid notes and count them by key.
        
        var counts = [Int](repeating: 0, count: 89) // counts[k + 1] is the number of notes of key k
        var collected: [MIDINote] = []
        collected.reserveCapacity(tracks.reduce(0) { $0 &+ $1.notes.count })
        for track in tracks {
            for note in track.notes {
                guard note.pitch >= 21 && note.pitch <= 108,
                      note.onset.isFinite && note.offset.isFinite,
                      note.onset <= note.offset else { continue }
                counts[Int(note.pitch) &- 20] &+= 1
                collected.append(note)
            }
        }
        
        // MARK: Group by key, a counting sort, then sort each key by onset.
        
        var starts = counts
        var key = 1
        while key < starts.count {
            starts[key] &+= starts[key &- 1]
            key &+= 1
        }
        
        var byKey = [MIDINote](unsafeUninitializedCapacity: collected.count) { buffer, initializedCount in
            var cursors = starts
            for note in collected {
                let lane = Int(note.pitch) &- 21
                (buffer.baseAddress! + cursors[lane]).initialize(to: note)
                cursors[lane] &+= 1
            }
            initializedCount = collected.count
        }
        _ = consume collected
        
        key = 0
        while key < 88 {
            byKey[starts[key]..<starts[key &+ 1]].sort { $0.onset < $1.onset }
            key &+= 1
        }
        
        // MARK: Clean each key in place, compacting the buffer.
        
        // `write` is where the next kept note goes; `cleanedStarts` are the boundaries of the kept notes.
        var cleanedStarts = [Int](repeating: 0, count: 89)
        var write = 0
        key = 0
        while key < 88 {
            let laneStart = write
            cleanedStarts[key] = laneStart
            var read = starts[key]
            while read < starts[key &+ 1] {
                let note = byKey[read]
                read &+= 1
                
                if write > laneStart {
                    let previous = write &- 1
                    if note.onset - byKey[previous].onset < gap {
                        // A second trigger of the same strike: merge it into the kept note.
                        byKey[previous].offset = Swift.max(byKey[previous].offset, note.offset)
                        byKey[previous].velocity = Swift.max(byKey[previous].velocity, note.velocity)
                        continue
                    }
                    
                    // End the kept note at least `gap` before this one; drop it if that leaves it too short.
                    byKey[previous].offset = Swift.min(byKey[previous].offset, note.onset - gap)
                    if byKey[previous].offset - byKey[previous].onset < gap {
                        write = previous
                    }
                }
                
                byKey[write] = note
                write &+= 1
            }
            key &+= 1
        }
        cleanedStarts[88] = write
        byKey.removeLast(byKey.count &- write)
        
        // MARK: Sort by (onset, pitch), recording each note's position for the lanes.
        
        var slots = Array(0..<byKey.count)
        slots.sort { lhs, rhs in
            let left = byKey[lhs]
            let right = byKey[rhs]
            return left.onset < right.onset || (left.onset == right.onset && left.pitch < right.pitch)
        }
        
        var members = [Int](repeating: 0, count: byKey.count)
        let notes = [MIDINote](unsafeUninitializedCapacity: byKey.count) { buffer, initializedCount in
            var position = 0
            while position < slots.count {
                let slot = slots[position]
                (buffer.baseAddress! + position).initialize(to: byKey[slot])
                members[slot] = position
                position &+= 1
            }
            initializedCount = slots.count
        }
        
        // MARK: Sustains, a gap apart at every pedal change.

        let sustains = Sustains(tracks.lazy.flatMap(\.sustains), minimumGap: gap)

        // MARK: Control and meta events, in time order.
        
        var channelEvents = tracks.flatMap(\.channelEvents.contents)
        channelEvents.sort { $0.onset < $1.onset }
        var metaEvents = tracks.flatMap(\.metaEvents) + source.tempo.metaEvents // the tempo track holds the time and key signatures of format-1 files
        metaEvents.sort { $0.timestamp < $1.timestamp }
        var rawData = tracks.flatMap(\.rawData)
        rawData.sort { $0.timestamp < $1.timestamp }
        
        self.notes = notes
        self.sustains = sustains
        self.channelEvents = channelEvents
        self.metaEvents = metaEvents
        self.rawData = rawData
        self.profile = profile
        
        let lanes = Lanes(members: members, starts: cleanedStarts, notes: notes)
        self.cache.lanes.withLock { $0 = lanes }
        
        assert(Self.isValid(notes: notes, lanes: lanes), "The cleaned-up track breaks its invariants.")
    }
    
    /// Creates an indexed track from notes and events that already meet its invariants, without cleaning them up.
    ///
    /// Transforms use this to return a new track: their output is already sorted and cleaned up, so no sort or cleanup is needed, and creating the track costs O(1). The ``lanes`` and other derived structures are computed on first use, as the new notes may differ from the ones they were built for.
    ///
    /// - Precondition: The arguments meet the invariants of ``IndexedTrack``, checked with an `assert`:
    ///   - `notes` are sorted by (onset, pitch), with pitches in `21...108`;
    ///   - the notes on each key are disjoint: each ends before the next one starts;
    ///   - `channelEvents` are sorted by onset, and `metaEvents` and `rawData` by timestamp.
    ///
    /// - Parameters:
    ///   - notes: The cleaned-up notes.
    ///   - sustains: The sustains, which are sorted and disjoint by construction.
    ///   - channelEvents: The channel events.
    ///   - metaEvents: The meta events.
    ///   - rawData: The raw messages.
    ///   - profile: The choices the analyses of this track make.
    package init(validated notes: [MIDINote], sustains: Sustains, channelEvents: [MIDIChannelEvent], metaEvents: [MIDIMetaEvent], rawData: [MIDIRawData], profile: any AnalysisProfile) {
        self.notes = notes
        self.sustains = sustains
        self.channelEvents = channelEvents
        self.metaEvents = metaEvents
        self.rawData = rawData
        self.profile = profile

        self.assertInvariants()
    }

    /// Creates an indexed track from validated input whose notes have the same order and keys as the notes `lanes` was built for, without cleaning them up.
    ///
    /// Transforms that only change times without reordering notes or changing their keys, such as ``applyingGap(ideal:minimumNoteLength:)``, use this to keep the layout of the lanes: the new ``lanes`` share `lanes`' layout and refer to the new notes, so the first access to them costs nothing.
    ///
    /// - Precondition: The arguments meet the invariants listed in ``init(validated:sustains:channelEvents:metaEvents:rawData:profile:)``, and `notes[i]` has the same key and (onset, pitch) rank as the note `lanes` was built for at index `i`. Both are checked with an `assert`.
    init(validated notes: [MIDINote], sustains: Sustains, channelEvents: [MIDIChannelEvent], metaEvents: [MIDIMetaEvent], rawData: [MIDIRawData], profile: any AnalysisProfile, reusingLayoutOf lanes: Lanes) {
        assert(notes.count == lanes.notes.count && zip(notes, lanes.notes).allSatisfy { $0.pitch == $1.pitch }, "The notes must have the same keys as the notes the lanes were built for.")

        self.notes = notes
        self.sustains = sustains
        self.channelEvents = channelEvents
        self.metaEvents = metaEvents
        self.rawData = rawData
        self.profile = profile

        let lanes = Lanes(members: lanes.members, starts: lanes.starts, notes: notes)
        self.cache.lanes.withLock { $0 = lanes }

        self.assertInvariants()
    }

    /// Asserts the invariants of ``IndexedTrack``, in debug builds only.
    private func assertInvariants() {
        assert(Self.isValid(notes: notes, lanes: self.lanes), "The notes break the invariants of an indexed track.")
        assert(channelEvents.indices.dropFirst().allSatisfy { channelEvents[$0 &- 1].onset <= channelEvents[$0].onset }, "The channel events must be sorted by onset.")
        assert(metaEvents.indices.dropFirst().allSatisfy { metaEvents[$0 &- 1].timestamp <= metaEvents[$0].timestamp }, "The meta events must be sorted by timestamp.")
        assert(rawData.indices.dropFirst().allSatisfy { rawData[$0 &- 1].timestamp <= rawData[$0].timestamp }, "The raw messages must be sorted by timestamp.")
    }
    
    /// Returns the track as a container with a single track, at a constant 120 BPM.
    ///
    /// - Complexity: O(*n*), where *n* is the number of events.
    public func makeContainer() -> MIDIContainer {
        var track = MIDITrack(
            notes: MIDINotes(self.notes),
            sustains: self.sustains,
            metaEvents: self.metaEvents,
            channelEvents: MIDIChannelEvents(self.channelEvents)
        )
        track.rawData = self.rawData
        return MIDIContainer(tracks: [track], tempo: MIDITempoTrack(tempos: [MIDITempoTrack.Tempo(timestamp: 0, beatsPerMinute: 120)]))
    }
    
    /// Returns whether the notes are sorted by (onset, pitch), and every lane is valid disjoint intervals.
    ///
    /// The sustains need no check, as ``MIDISustainEvents`` is sorted and disjoint by construction.
    ///
    /// For debug-only `assert`s.
    static func isValid(notes: [MIDINote], lanes: Lanes) -> Bool {
        var index = 1
        while index < notes.count {
            let previous = notes[index &- 1]
            let current = notes[index]
            guard previous.onset < current.onset || (previous.onset == current.onset && previous.pitch < current.pitch) else { return false }
            index &+= 1
        }
        
        for pitch in 21...108 as ClosedRange<UInt8> {
            guard lanes[pitch].isValidDisjointIntervals() else { return false }
        }
        return true
    }
    
}
