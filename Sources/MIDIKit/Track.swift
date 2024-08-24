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
    
    public var notes: [Note]
    
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
            _quantize(value: &self.notes[i].offset)
        }
        
        for i in 0..<self.sustains.count {
            _quantize(value: &self.sustains[i].onset)
            _quantize(value: &self.sustains[i].offset)
        }
    }
    
    
    public init(notes: [Note] = [], sustains: [SustainEvent] = [], metaEvents: [MetaEvent] = []) {
        self.notes = notes
        self.sustains = sustains
        self.metaEvents = metaEvents
    }
    
    public typealias Note = MIDINote
    
    public struct SustainEvent: Sendable, Equatable {
        
        public var onset: MusicTimeStamp
        
        public var offset: MusicTimeStamp
        
        public init(onset: MusicTimeStamp, offset: MusicTimeStamp) {
            self.onset = onset
            self.offset = offset
        }
        
    }
    
    /// A wrapper for meta event
    ///
    /// Byte layout
    /// ```
    /// - 3 // metaEventType
    /// - 0 // unused1
    /// - 0 // unused2
    /// - 0 // unused3
    /// - 5 // dataLength 1
    /// - 0 // dataLength 2
    /// - 0 // dataLength 3
    /// - 0 // dataLength 4
    /// - 80 // data
    /// - 105 // ...
    /// - 97
    /// - 110
    /// - 111
    /// ```
    public struct MetaEvent: Sendable, Equatable {
        
        public let timestamp: MusicTimeStamp
        
        public let type: UInt8
        
        public let data: Data
        
        
        func withUnsafePointer<T>(body: (UnsafePointer<MIDIMetaEvent>) throws -> T) rethrows -> T {
            let data = Swift.withUnsafePointer(to: type) { pointer in
                Data(bytes: pointer, count: 1)
            } + Data(repeating: 0, count: 3) + Swift.withUnsafePointer(to: UInt32(data.count)) { pointer in
                Data(bytes: pointer, count: 4)
            } + data
            
            return try data.withUnsafeBytes { pointer in
                try body(pointer.baseAddress!.assumingMemoryBound(to: MIDIMetaEvent.self))
            }
        }
        
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
        let type = switch AVMIDIMetaEvent.EventType(rawValue: Int(self.type)) {
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
        
        let content: Any? = switch AVMIDIMetaEvent.EventType(rawValue: Int(self.type)) {
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
