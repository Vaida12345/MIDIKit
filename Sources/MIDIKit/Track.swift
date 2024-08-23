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


public struct MIDITrack: CustomStringConvertible, CustomDetailedStringConvertible {
    
    public var notes: [Note]
    
    public var sustains: [SustainEvent]
    
    public var metaEvents: [MetaEvent]
    
    
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
        
        for metaEvent in metaEvents {
            var event = metaEvent.event
            MusicTrackNewMetaEvent(musicTrack, metaEvent.timestamp, &event)
        }
        
        return musicTrack
    }
    
    
    public init(notes: [Note] = [], sustains: [SustainEvent] = [], metaEvents: [MetaEvent] = []) {
        self.notes = notes
        self.sustains = sustains
        self.metaEvents = metaEvents
    }
    
    public typealias Note = MIDINote
    
    public struct SustainEvent {
        
        let onset: MusicTimeStamp
        
        let offset: MusicTimeStamp
        
    }
    
    public struct MetaEvent {
        
        let timestamp: MusicTimeStamp
        
        let event: MIDIMetaEvent
        
        /// The extracted data, only for printing purposes.
        let data: Data
        
    }
    
    
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


@available(macOS 12.0, *)
extension MIDITrack.SustainEvent: CustomStringConvertible {
    
    public var description: String {
        "Sustain(range: \(onset.formatted(.number.precision(.fractionLength(2)))) - \(offset.formatted(.number.precision(.fractionLength(2)))))"
    }
    
}


@available(macOS 13.0, *)
extension MIDITrack.MetaEvent: CustomStringConvertible {
    
    public var description: String {
        let type = switch AVMIDIMetaEvent.EventType(rawValue: Int(event.metaEventType)) {
        case .copyright: "copyright"
        case .cuePoint: "cue point"
        case .endOfTrack: "end of track"
        case .instrument: "instrument"
        case .keySignature: "key signature"
        case .lyric: "lyric"
        case .marker: "marker"
        case .midiChannel: "midi channel"
        case .midiPort: "midi port"
        case .proprietaryEvent: "proprietary event"
        case .sequenceNumber: "sequence number"
        case .smpteOffset: "SMPTE time offset"
        case .tempo: "tempo"
        case .text: "text"
        case .timeSignature: "time signature"
        case .trackName: "track name"
        case .none: "(unknown)"
        default:
            fatalError()
        }
        
        let content: Any? = switch AVMIDIMetaEvent.EventType(rawValue: Int(event.metaEventType)) {
        case .trackName:
            String(data: self.data, encoding: .utf8) .map { "\"" + $0 + "\"" }
            
        default:
            "(" + self.data.map({ $0.description }).joined(separator: ", ") + ")"
        }
        
        if let content {
            return "MetaEvent(timestamp: \(timestamp), type: \(type), content: \(content))"
        } else {
            return "MetaEvent(timestamp: \(timestamp), type: \(type), data: \(data))"
        }
    }
    
}
