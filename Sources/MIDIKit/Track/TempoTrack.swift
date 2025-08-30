//
//  MIDITempoTrack.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

import AudioToolbox
import DetailedDescription
import AVFoundation


public struct MIDITempoTrack: Sendable, CustomStringConvertible, DetailedStringConvertible, Equatable, ArrayRepresentable {
    
    public var events: [MIDIMetaEvent]
    
    public var contents: [Tempo]
    
    
    public mutating func setTimeSignature(beatsPerMeasure: UInt8, beatsPerNote: UInt8) {
        var data = Data(capacity: 4)
        data.append(beatsPerMeasure)
        data.append(UInt8(log2(Double(beatsPerNote))))
        data.append(24)
        data.append(8)
        
        if let eventIndex = events.firstIndex(where: { AVMIDIMetaEvent.EventType(rawValue: Int($0.type)) == .timeSignature }) {
            events[eventIndex].data = data
        } else {
            events.append(MIDITrack.MetaEvent(timestamp: 0, type: UInt8(AVMIDIMetaEvent.EventType.timeSignature.rawValue), data: data))
        }
    }
    
    /// Creates a fresh tempo track
    ///
    /// If you don't specify the meta events, a default one of 4/4 will be used on write. The default one is equivalent to
    /// ```swift
    /// [MIDIMetaEvent(timestamp: 0.0, type: .timeSignature, data: Data([4, 2, 24, 8]))]
    /// ```
    ///
    /// CoreMIDI will also insert a default tempo of 120.
    ///
    /// - SeeAlso: ``MIDIMetaEvent/defaultTimeSignature``, ``MIDITempoTrack/Tempo/default``
    public init(events: [MIDITrack.MetaEvent] = [], tempos: [Tempo] = []) {
        self.events = events
        self.contents = tempos
    }
    
    public init(_ contents: [Element]) {
        self.init(events: [], tempos: contents)
    }
    
    
    public var description: String {
        self.detailedDescription
    }
    
    public func detailedDescription(using descriptor: DetailedDescription.Descriptor<MIDITempoTrack>) -> any DescriptionBlockProtocol {
        descriptor.container {
            descriptor.sequence(for: \.contents)
            descriptor.sequence(for: \.events)
        }
    }
    
    public typealias Element = Tempo
    
    public struct Tempo: Sendable, Equatable {
        
        public var timestamp: MusicTimeStamp
        
        public var tempo: Double
        
        
        /// The default tempo of 120.
        ///
        /// This is the tempo event CoreMIDI uses on write when on is specified.
        public static var `default`: Tempo {
            Tempo(timestamp: 0.0, tempo: 120.0)
        }
        
        public init(timestamp: MusicTimeStamp, tempo: Double) {
            self.timestamp = timestamp
            self.tempo = tempo
        }
    }
    
}
