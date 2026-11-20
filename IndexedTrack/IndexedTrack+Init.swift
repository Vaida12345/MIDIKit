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
    /// - Sustains that overlap or touch are merged, and invalid ones are dropped.
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
        
        // MARK: Sustains, merged when they overlap or touch.
        
        var sortedSustains = tracks.flatMap(\.sustains).filter { sustain in
            sustain.onset.isFinite && sustain.offset.isFinite && sustain.onset <= sustain.offset
        }
        sortedSustains.sort { $0.onset < $1.onset }
        var sustains: [MIDISustainEvent] = []
        sustains.reserveCapacity(sortedSustains.count)
        for sustain in sortedSustains {
            if let last = sustains.last, sustain.onset <= last.offset {
                sustains[sustains.count &- 1].offset = Swift.max(last.offset, sustain.offset)
            } else {
                sustains.append(sustain)
            }
        }
        
        // MARK: Control and meta events, in time order.
        
        var controlEvents = tracks.flatMap(\.controlEvents.contents)
        controlEvents.sort { $0.onset < $1.onset }
        var metaEvents = tracks.flatMap(\.metaEvents)
        metaEvents.sort { $0.timestamp < $1.timestamp }
        
        self.notes = notes
        self.sustains = sustains
        self.controlEvents = controlEvents
        self.metaEvents = metaEvents
        self.profile = profile
        
        let lanes = Lanes(members: members, starts: cleanedStarts, notes: notes)
        self.cache.lanes.withLock { $0 = lanes }
        
        assert(Self.isValid(notes: notes, lanes: lanes, sustains: sustains), "The cleaned-up track breaks its invariants.")
    }
    
    /// Returns the track as a container with a single track, at a constant 120 BPM.
    ///
    /// - Complexity: O(*n*), where *n* is the number of events.
    public func makeContainer() -> MIDIContainer {
        let track = MIDITrack(
            notes: MIDINotes(self.notes),
            sustains: MIDISustainEvents(self.sustains),
            metaEvents: self.metaEvents,
            controlEvents: MIDIControlEvents(self.controlEvents)
        )
        return MIDIContainer(tracks: [track], tempo: MIDITempoTrack(tempos: [MIDITempoTrack.Tempo(timestamp: 0, tempo: 120)]))
    }
    
    /// Returns whether the notes are sorted by (onset, pitch), every lane is valid disjoint intervals, and so are the sustains.
    ///
    /// For debug-only `assert`s.
    static func isValid(notes: [MIDINote], lanes: Lanes, sustains: [MIDISustainEvent]) -> Bool {
        var index = 1
        while index < notes.count {
            let previous = notes[index &- 1]
            let current = notes[index]
            guard previous.onset < current.onset || (previous.onset == current.onset && previous.pitch < current.pitch) else { return false }
            index &+= 1
        }
        
        for pitch in 21...108 as ClosedRange<UInt8> {
            guard lanes[lane: pitch].isValidDisjointIntervals() else { return false }
        }
        
        index = 0
        while index < sustains.count {
            guard sustains[index].onset <= sustains[index].offset else { return false }
            if index &+ 1 < sustains.count && !(sustains[index].offset < sustains[index &+ 1].onset) { return false }
            index &+= 1
        }
        return true
    }
    
}
