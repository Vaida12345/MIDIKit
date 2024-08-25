//
//  Track.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

import Foundation
import AudioToolbox
import DetailedDescription
import AVFoundation


public struct MIDITrack: CustomStringConvertible, CustomDetailedStringConvertible, Sendable, Equatable {
    
    public var notes: Notes
    
    public var sustains: [SustainEvent]
    
    public var metaEvents: [MetaEvent]
    
    /// The range of the notes in the track.
    public var range: ClosedRange<MusicTimeStamp> {
        let onsets = notes.map(\.onset)
        let offsets = notes.map(\.offset)
        
        return ClosedRange(uncheckedBounds: (onsets.min() ?? 0, offsets.max() ?? 0))
    }
    
    
    internal func makeTrack(sequence: MusicSequence) -> MusicTrack {
        var musicTrack: MusicTrack?
        MusicSequenceNewTrack(sequence, &musicTrack)
        guard let musicTrack else {
            fatalError()
        }
        
        for metaEvent in metaEvents {
            _ = metaEvent.withUnsafePointer { pointer in
                MusicTrackNewMetaEvent(musicTrack, metaEvent.timestamp, pointer)
            }
        }
        
        for note in notes {
            var message = MIDINoteMessage(channel: note.channel, note: note.note, velocity: note.velocity, releaseVelocity: note.releaseVelocity, duration: Float32(note.offset - note.onset))
            MusicTrackNewMIDINoteEvent(musicTrack, note.onset, &message)
        }
        
        for sustain in sustains {
            var first = MIDIChannelMessage(status: 0xB0, data1: 64, data2: 127, reserved: 0)
            var last  = MIDIChannelMessage(status: 0xB0, data1: 64, data2: 0,   reserved: 0)
            MusicTrackNewMIDIChannelEvent(musicTrack, sustain.onset, &first)
            MusicTrackNewMIDIChannelEvent(musicTrack, sustain.offset, &last)
        }
        
        return musicTrack
    }
    
    public mutating func appendNotes(from rhs: MIDITrack) {
        self.notes.append(contentsOf: rhs.notes)
    }
    
    /// Quantize the track.
    ///
    /// In 4/4, a `discreteValue` of 1 indicates a quarter note.
    public mutating func quantize(by discreteValue: MusicTimeStamp) {
        func _quantize(value: inout MusicTimeStamp) {
            value = (value / discreteValue).rounded(.toNearestOrAwayFromZero) * discreteValue
        }
        
        for i in 0..<self.notes.count {
            _quantize(value: &self.notes[i].onset)
            _quantize(value: &self.notes[i].duration)
        }
        
        for i in 0..<self.sustains.count {
            _quantize(value: &self.sustains[i].onset)
            _quantize(value: &self.sustains[i].offset)
        }
    }
    
    
    public init(notes: [Note] = [], sustains: [SustainEvent] = [], metaEvents: [MetaEvent] = []) {
        self.notes = Notes(notes: notes)
        self.sustains = sustains
        self.metaEvents = metaEvents
    }
    
    public init(notes: Notes, sustains: [SustainEvent] = [], metaEvents: [MetaEvent] = []) {
        self.notes = notes
        self.sustains = sustains
        self.metaEvents = metaEvents
    }
    
    public typealias Note = MIDINote
                       
    public typealias Notes = MIDINotes
    
    public typealias SustainEvent = MIDISustainEvent
    
    public typealias MetaEvent = MIDIMetaEvent
    
    
    public var description: String {
        self.detailedDescription
    }
    
    public func detailedDescription(using descriptor: DetailedDescription.Descriptor<MIDITrack>) -> any DescriptionBlockProtocol {
        descriptor.container {
            descriptor.sequence(for: \.notes)
            descriptor.sequence(for: \.sustains)
            descriptor.sequence(for: \.metaEvents)
        }
    }
    
}
