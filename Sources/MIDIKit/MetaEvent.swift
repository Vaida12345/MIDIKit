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
public struct MIDIMetaEvent: Sendable, Equatable {
    
    public var timestamp: MusicTimeStamp
    
    public var type: UInt8
    
    public var data: Data
    
    
    func withUnsafePointer<T>(body: (UnsafePointer<AudioToolbox.MIDIMetaEvent>) throws -> T) rethrows -> T {
        let data = Swift.withUnsafePointer(to: type) { pointer in
            Data(bytes: pointer, count: 1)
        } + Data(repeating: 0, count: 3) + Swift.withUnsafePointer(to: UInt32(data.count)) { pointer in
            Data(bytes: pointer, count: 4)
        } + data
        
        return try data.withUnsafeBytes { pointer in
            try body(pointer.baseAddress!.assumingMemoryBound(to: AudioToolbox.MIDIMetaEvent.self))
        }
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
            fatalError()
        }
        
        let content: Any? = switch AVMIDIMetaEvent.EventType(rawValue: Int(self.type)) {
        case .trackName, .instrument:
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
