//
//  Track + Toolbox.swift
//  MIDIKit
//
//  Created by Vaida on 2025-06-10.
//

import AudioToolbox


extension MIDITrack {
    
    /// Burns the track onto `sequence`, and returns the burnt track.
    ///
    /// - Parameter grid: The tick grid of the file the sequence will be written to. Times are rounded to it, and notes and sustains last at least one tick.
    @discardableResult
    internal func makeTrack(sequence: MusicSequence, grid: TickGrid = TickGrid(resolution: nil)) -> MusicTrack {
        var musicTrack: MusicTrack!
        MusicSequenceNewTrack(sequence, &musicTrack)
        
        metaEvents.forEach { _, metaEvent in
            metaEvent.withUnsafePointer { pointer in
                _ = MusicTrackNewMetaEvent(musicTrack, grid.snap(metaEvent.timestamp), pointer)
            }
        }
        
        // CoreMIDI keeps the order of insertion for events at the same time, so the raw data and channel events, such as a GM reset or a program change, go before the notes they set up.
        rawData.forEach { _, raw in
            raw.withUnsafePointer { pointer in
                _ = MusicTrackNewMIDIRawDataEvent(musicTrack, grid.snap(raw.timestamp), pointer)
            }
        }
        
        channelEvents.forEach { _, event in
            var message = event.channelMessage
            MusicTrackNewMIDIChannelEvent(musicTrack, grid.snap(event.onset), &message)
        }
        
        notes.forEach { _, note in
            let (onset, offset) = grid.snap(onset: note.onset, offset: note.offset)
            var message = MIDINoteMessage(channel: note.channel, note: note.pitch, velocity: note.velocity, releaseVelocity: note.releaseVelocity, duration: grid.duration(offset - onset))
            MusicTrackNewMIDINoteEvent(musicTrack, onset, &message)
        }
        
        sustains.forEach { _, sustain in
            let (onset, offset) = grid.snap(onset: sustain.onset, offset: sustain.offset)
            var first = MIDIChannelMessage(status: 0xB0, data1: 64, data2: 127, reserved: 0)
            var last  = MIDIChannelMessage(status: 0xB0, data1: 64, data2: 0,   reserved: 0)
            MusicTrackNewMIDIChannelEvent(musicTrack, onset, &first)
            MusicTrackNewMIDIChannelEvent(musicTrack, offset, &last)
        }
        
        return musicTrack
    }
    
}


/// The tick grid of a MIDI file, to which times are rounded before writing.
///
/// CoreMIDI writes each event as the number of ticks since the previous one, rounding every such gap on its own. Times off the grid therefore accumulate rounding errors along the file: a file stored at 384 ticks per beat drifts by about 0.17 beat over 1,000 beats when written at 4,800. Rounding each absolute time to the grid first makes every gap a whole number of ticks, so each time is off by at most half a tick, and the error never accumulates.
@usableFromInline
struct TickGrid {
    
    /// The ticks per beat, or `nil` to keep exact times.
    let resolution: Double?
    
    @usableFromInline
    init(resolution: Int16?) {
        self.resolution = resolution.map(Double.init)
    }
    
    /// Rounds `time` to the nearest tick. Times that aren't finite are returned as they are.
    func snap(_ time: MusicTimeStamp) -> MusicTimeStamp {
        guard let resolution, time.isFinite else { return time }
        return (time * resolution).rounded() / resolution
    }
    
    /// Converts a duration to the `Float32` a note message stores.
    ///
    /// On a grid, the duration is rounded down to a `Float32` when that keeps it within half a tick: a note that ends exactly where the next note on its key starts would otherwise end a hair after it, and Core Audio would write the next note-on before this note-off, losing a note. From about 512 beats, a `Float32` step is larger than half a tick, so the duration is rounded to the nearest `Float32` instead, which keeps it on its tick.
    func duration(_ duration: Double) -> Float32 {
        let rounded = Float32(duration)
        guard let resolution, Double(rounded) > duration else { return rounded }
        let down = rounded.nextDown
        return (duration - Double(down)) * resolution < 0.5 ? down : rounded
    }
    
    /// Rounds an interval to the grid, keeping it at least one tick long.
    func snap(onset: MusicTimeStamp, offset: MusicTimeStamp) -> (onset: MusicTimeStamp, offset: MusicTimeStamp) {
        guard let resolution, onset.isFinite, offset.isFinite else { return (onset, offset) }
        let onsetTick = (onset * resolution).rounded()
        let offsetTick = Swift.max((offset * resolution).rounded(), onsetTick + 1)
        return (onsetTick / resolution, offsetTick / resolution)
    }
    
}
