//
//  GenericProfile.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import MIDIKit


/// The profile that assumes nothing about where the notes came from.
public struct GenericProfile: AnalysisProfile {
    
    /// Creates the generic profile.
    public init() {

    }

    /// Groups the notes of `track` into chords with ``ChordArbiter/generic``.
    public func formChords(in track: IndexedTrack) -> IndexedTrack.Chords {
        ChordArbiter.generic.formChords(in: track)
    }

    /// Finds the downbeats of `track` with ``DownbeatTracker/generic``.
    public func downbeats(in track: IndexedTrack, prior: [Double]) -> [Double] {
        DownbeatTracker.generic.downbeats(in: track, prior: prior)
    }

    /// Returns `track` without the stray quiet notes that transcribers such as PianoTranscription tend to produce.
    ///
    /// On each key, a run of consecutive notes no louder than `threshold`, each starting within `proximityThreshold` after the previous one ends, is removed when the note before the run also ends within `proximityThreshold` before it. That note is then extended to where the run ended. The note before the run is louder than `threshold`, or is the first note on the key; the first note on a key never starts a run.
    ///
    /// Only notes and offsets change: sustains, channel events, meta events and the profile of `track` are kept.
    ///
    /// - Parameters:
    ///   - track: The track to clean up.
    ///   - threshold: The velocity at or under which a note may be an artifact.
    ///   - proximityThreshold: How close, in beats, consecutive notes on a key must be to belong to one run. It must be finite and at least zero.
    ///
    /// - Complexity: O(*n*), where *n* is the number of notes.
    public func removingArtifacts(from track: IndexedTrack, threshold: UInt8, proximityThreshold: Double) -> IndexedTrack {
        precondition(proximityThreshold.isFinite && proximityThreshold >= 0, "proximityThreshold must be finite and at least zero")
        guard !track.notes.isEmpty else { return track }

        let lanes = track.lanes
        var notes = track.notes
        var isRemoved = [Bool](repeating: false, count: notes.count)
        var removedCount = 0

        var key = 0
        while key < 88 {
            let laneStart = lanes.starts[key]
            let laneEnd = lanes.starts[key &+ 1]

            // From the last note back. The run is `runStart...runEnd` in member positions, and there is none while `runEnd < 0`. Only notes after the current one are ever removed, so the note after it is always still there.
            var runStart = -1
            var runEnd = -1
            var position = laneEnd &- 1
            while position >= laneStart {
                let current = lanes.members[position]
                let next = position &+ 1
                let isClose = next < laneEnd && notes[lanes.members[next]].onset - notes[current].offset < proximityThreshold

                if notes[current].velocity <= threshold && position > laneStart {
                    if runEnd < 0 {
                        runStart = position
                        runEnd = position
                    } else if isClose {
                        runStart = position
                    } else {
                        runEnd = -1
                    }
                } else {
                    if runEnd >= 0 && isClose {
                        // Remove the run, and extend this note over it.
                        notes[current].offset = notes[lanes.members[runEnd]].offset
                        var removed = runStart
                        while removed <= runEnd {
                            isRemoved[lanes.members[removed]] = true
                            removed &+= 1
                        }
                        removedCount &+= runEnd &- runStart &+ 1
                    }
                    runEnd = -1
                }

                position &-= 1
            }
            key &+= 1
        }

        guard removedCount > 0 else { return track }

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

        return IndexedTrack(validated: kept, sustains: track.sustains, channelEvents: track.channelEvents, metaEvents: track.metaEvents, rawData: track.rawData, profile: track.profile)
    }

}


extension AnalysisProfile where Self == GenericProfile {
    
    /// The profile that assumes nothing about where the notes came from.
    public static var generic: GenericProfile {
        GenericProfile()
    }
    
}
