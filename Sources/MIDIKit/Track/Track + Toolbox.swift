//
//  Track + Toolbox.swift
//  MIDIKit
//
//  Created by Vaida on 2025-06-10.
//

import AudioToolbox


extension MIDITrack {
    
    /// Burn the track onto the `sequence`, and returns the burnt track.
    @discardableResult
    internal func makeTrack(sequence: MusicSequence) -> MusicTrack {
        var musicTrack: MusicTrack!
        MusicSequenceNewTrack(sequence, &musicTrack)
        
        metaEvents.forEach { _, metaEvent in
            metaEvent.withUnsafePointer { pointer in
                _ = MusicTrackNewMetaEvent(musicTrack, metaEvent.timestamp, pointer)
            }
        }
        
        notes.forEach { _, note in
            var message = MIDINoteMessage(channel: note.channel, note: note.note, velocity: note.velocity, releaseVelocity: note.releaseVelocity, duration: Float32(note.offset - note.onset))
            MusicTrackNewMIDINoteEvent(musicTrack, note.onset, &message)
        }
        
        sustains.forEach { _, sustain in
            var first = MIDIChannelMessage(status: 0xB0, data1: 64, data2: 127, reserved: 0)
            var last  = MIDIChannelMessage(status: 0xB0, data1: 64, data2: 0,   reserved: 0)
            MusicTrackNewMIDIChannelEvent(musicTrack, sustain.onset, &first)
            MusicTrackNewMIDIChannelEvent(musicTrack, sustain.offset, &last)
        }
        
        controlEvents.forEach { _, control in
            var message = MIDIChannelMessage(status: 0xB0, data1: control.channel, data2: control.velocity, reserved: 0)
            MusicTrackNewMIDIChannelEvent(musicTrack, control.onset, &message)
        }
        
        // there is no way to write back raw data, as AudioToolbox raw data expects encoding `Data` as `UInt8`, which is unsafe in Swift.
        
        return musicTrack
    }
    
}
