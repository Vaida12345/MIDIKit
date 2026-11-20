//
//  Indexed+Warped.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import MIDIKit


extension IndexedTrack {
    
    /// Returns this track with every time mapped through `warp`.
    ///
    /// The onsets and offsets of the notes and of the sustains, the onsets of the channel events and the timestamps of the meta events and raw data are mapped. Pitches, velocities, channels and the ``profile`` are kept.
    ///
    /// The result is built like any track, from ``makeContainer()``, so its invariants hold again whatever the warp did. As a warp is strictly increasing, it never changes the order of events, but a warp that slows down, with a slope under 1, brings events closer: two notes on one key that end up less than `1/128` beat apart are merged, a note that ends too close to the next on its key is shortened, and sustains that touch merge.
    ///
    /// A warp extends its first segment before its first knot, so it can map times before the first paired chord, such as the time signature at 0, below 0. Those times are moved to 0, as a file cannot hold events before its start.
    ///
    /// To make a sheet follow a performance, warp it by the result of ``timeWarp(to:parameters:)``.
    ///
    /// - Parameter warp: The warp to apply, mapping the beats of this track to the beats of the result. Both are in beats at 120 BPM.
    ///
    /// - Complexity: O(*n* log *k* + *n* log *n*), where *n* is the number of events and *k* the number of knots, which includes creating the track.
    public func warped(by warp: TimeWarp) -> IndexedTrack {
        var container = self.makeContainer()
        
        /// Maps a time through `warp`, moving times before 0 to 0.
        func map(_ time: Double) -> Double {
            Swift.max(warp.map(time), 0)
        }
        
        // `makeContainer()` builds a single track.
        container.tracks[0].notes.contents.withUnsafeMutableBufferPointer { notes in
            var index = 0
            while index < notes.count {
                notes[index].onset = map(notes[index].onset)
                notes[index].offset = map(notes[index].offset)
                index &+= 1
            }
        }
        
        container.tracks[0].sustains = container.tracks[0].sustains.transformed { MIDISustainEvent(onset: map($0.onset), offset: map($0.offset)) }
        
        container.tracks[0].channelEvents.contents.withUnsafeMutableBufferPointer { events in
            var index = 0
            while index < events.count {
                events[index].onset = map(events[index].onset)
                index &+= 1
            }
        }
        
        var index = 0
        while index < container.tracks[0].metaEvents.count {
            container.tracks[0].metaEvents[index].timestamp = map(container.tracks[0].metaEvents[index].timestamp)
            index &+= 1
        }
        
        // `makeContainer()` puts the time signatures in the tempo track.
        index = 0
        while index < container.tempo.metaEvents.count {
            container.tempo.metaEvents[index].timestamp = map(container.tempo.metaEvents[index].timestamp)
            index &+= 1
        }
        
        index = 0
        while index < container.tracks[0].rawData.count {
            container.tracks[0].rawData[index].timestamp = map(container.tracks[0].rawData[index].timestamp)
            index &+= 1
        }
        
        return IndexedTrack(container, profile: self.profile)
    }
    
}
