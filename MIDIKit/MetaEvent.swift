//
//  MetaEvent.swift
//  MIDIKit
//
//  Created by Vaida on 8/26/24.
//

import AudioToolbox
import AVFAudio


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
public struct MIDIMetaEvent: Sendable, Hashable {
    
    public var timestamp: MusicTimeStamp
    
    public var type: UInt8
    
    public var data: Data
    
    
    @inlinable
    public init(timestamp: MusicTimeStamp, type: UInt8, data: Data) {
        self.timestamp = timestamp
        self.type = type
        self.data = data
    }
    
    @inlinable
    public init(timestamp: MusicTimeStamp, type: AVMIDIMetaEvent.EventType, data: Data) {
        self.timestamp = timestamp
        self.type = UInt8(type.rawValue)
        self.data = data
    }
    
    /// The default time signature meta event CoreMIDI uses on write when none is specified.
    ///
    /// The default meta event specifies a 4/4 time signature, one metronome click per quarter note, and the default 32nd-note division.
    @inlinable
    public static var defaultTimeSignature: MIDIMetaEvent {
        MIDITimeSignature.default.event()
    }
    
    
    /// Calls `body` with a pointer to an `AudioToolbox.MIDIMetaEvent` that holds this event.
    ///
    /// `MIDIMetaEvent` ends in a C flexible array member, like `MIDIRawData`; see ``MIDIRawData`` for why the buffer is built as raw memory. Its header is the type, 3 unused bytes, and the `UInt32` length.
    func withUnsafePointer<T>(body: (UnsafePointer<AudioToolbox.MIDIMetaEvent>) throws -> T) rethrows -> T {
        let type = self.type
        let length = UInt32(self.data.count)
        return try withFlexibleBuffer(header: { header in
            header.storeBytes(of: type, as: UInt8.self)
            header.storeBytes(of: length, toByteOffset: 4, as: UInt32.self)
        }, headerSize: 8, data: self.data, as: AudioToolbox.MIDIMetaEvent.self, body: body)
    }
    
}


@available(macOS 13.0, *)
extension MIDIMetaEvent: CustomStringConvertible {
    
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
            "(unknown type \(self.type))"
        }
        
        let content: Any? = switch AVMIDIMetaEvent.EventType(rawValue: Int(self.type)) {
        case .trackName, .instrument:
            String(data: self.data, encoding: .utf8).map { "\"" + $0 + "\"" }
            
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
