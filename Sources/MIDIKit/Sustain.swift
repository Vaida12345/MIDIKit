//
//  Sustain.swift
//  MIDIKit
//
//  Created by Vaida on 8/26/24.
//

import AudioToolbox


public struct MIDISustainEvent: Sendable, Equatable, Interval {
    
    public var onset: MusicTimeStamp
    
    public var offset: MusicTimeStamp
    
    /// The duration of the note, on set, it changes the ``offset``, while ``onset`` remains the same.
    public var duration: Double {
        get {
            self.offset - self.onset
        }
        set {
            self.offset = self.onset + newValue
        }
    }
    
    public init(onset: MusicTimeStamp, offset: MusicTimeStamp) {
        self.onset = onset
        self.offset = offset
    }
    
}


@available(macOS 12.0, *)
extension MIDISustainEvent: CustomStringConvertible {
    
    public var description: String {
        "Sustain(range: \(onset.formatted(.number.precision(.fractionLength(2)))) - \(offset.formatted(.number.precision(.fractionLength(2)))))"
    }
    
}
