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
    /// To make a sheet follow a performance, warp it by the result of ``timeWarp(to:parameters:)``.
    ///
    /// - Parameter warp: The warp to apply, mapping the beats of this track to the beats of the result. Both are in beats at 120 BPM.
    ///
    /// - Complexity: O(*n* log *k* + *n* log *n*), where *n* is the number of events and *k* the number of knots, which includes creating the track.
    public func warped(by warp: TimeWarp) -> IndexedTrack {
        var container = self.makeContainer()
        
        // `makeContainer()` builds a single track.
        container.tracks[0].notes.contents.withUnsafeMutableBufferPointer { notes in
            var index = 0
            while index < notes.count {
                notes[index].onset = warp.map(notes[index].onset)
                notes[index].offset = warp.map(notes[index].offset)
                index &+= 1
            }
        }
        
        container.tracks[0].sustains.contents.withUnsafeMutableBufferPointer { sustains in
            var index = 0
            while index < sustains.count {
                sustains[index].onset = warp.map(sustains[index].onset)
                sustains[index].offset = warp.map(sustains[index].offset)
                index &+= 1
            }
        }
        
        container.tracks[0].channelEvents.contents.withUnsafeMutableBufferPointer { events in
            var index = 0
            while index < events.count {
                events[index].onset = warp.map(events[index].onset)
                index &+= 1
            }
        }
        
        var index = 0
        while index < container.tracks[0].metaEvents.count {
            container.tracks[0].metaEvents[index].timestamp = warp.map(container.tracks[0].metaEvents[index].timestamp)
            index &+= 1
        }
        
        index = 0
        while index < container.tracks[0].rawData.count {
            container.tracks[0].rawData[index].timestamp = warp.map(container.tracks[0].rawData[index].timestamp)
            index &+= 1
        }
        
        return IndexedTrack(container, profile: self.profile)
    }
    
}
