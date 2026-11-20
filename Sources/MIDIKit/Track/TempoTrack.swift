//
//  MIDITempoTrack.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

import AudioToolbox
import DetailedDescription
import AVFoundation


public struct MIDITempoTrack: Sendable, CustomStringConvertible, DetailedStringConvertible, Equatable {
    
    public var events: [MIDIMetaEvent]
    
    public var contents: [Tempo]
    
    
    /// The time signature of the track: the first valid time-signature meta event in ``events``.
    ///
    /// Setting a time signature replaces the data of the first time-signature event, or adds one at time 0 if there is none. Setting `nil` removes every time-signature event.
    ///
    /// A file written without a time signature gets ``MIDITimeSignature/default``, 4/4, from CoreMIDI.
    public var timeSignature: MIDITimeSignature? {
        get {
            var index = 0
            while index < self.events.count {
                if let signature = MIDITimeSignature(self.events[index]) { return signature }
                index &+= 1
            }
            return nil
        }
        set {
            guard let newValue else {
                self.events.removeAll { $0.type == 0x58 }
                return
            }
            if let index = self.events.firstIndex(where: { $0.type == 0x58 }) {
                self.events[index].data = newValue.data
            } else {
                self.events.append(newValue.event(at: 0))
            }
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
