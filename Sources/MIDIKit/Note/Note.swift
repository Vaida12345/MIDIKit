//
//  Note.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

import Foundation
import AudioToolbox
import SwiftUI


/// A MIDI note message.
///
/// `MIDINote`s are comparable using their ``onset``.
public struct MIDINote: Sendable, Hashable, Interval, Comparable {
    
    /// The onset, in beats.
    public var onset: MusicTimeStamp
    public var offset: MusicTimeStamp
    /// The key
    public var note: UInt8
    public var velocity: UInt8
    public var channel: UInt8
    public var releaseVelocity: UInt8
    
    /// The duration of the note, on set, it changes the ``offset``, while ``onset`` remains the same.
    @inlinable
    public var duration: Double {
        get {
            self.offset - self.onset
        }
        set {
            self.offset = self.onset + newValue
        }
    }
    
    /// The key, alias to `note`.
    @inlinable
    public var pitch: UInt8 {
        get { self.note }
        set { self.note = newValue }
    }
    
    @inlinable
    public init(onset: MusicTimeStamp, offset: MusicTimeStamp, note: UInt8, velocity: UInt8, channel: UInt8 = 0, releaseVelocity: UInt8 = 0) {
        assert(channel <= 15)
        
        self.onset = onset
        self.offset = offset
        self.note = note
        self.velocity = velocity
        self.channel = channel
        self.releaseVelocity = releaseVelocity
    }
    
    @inlinable
    internal init(onset: Double, message: MIDINoteMessage) {
        self.onset = onset
        self.offset = self.onset + Double(message.duration)
        self.note = message.note
        self.velocity = message.velocity
        self.channel = message.channel
        self.releaseVelocity = message.releaseVelocity
    }
    
    public static func < (lhs: MIDINote, rhs: MIDINote) -> Bool {
        lhs.onset < rhs.onset
    }
    
}


extension MIDINote: CustomStringConvertible {
    
    @inlinable
    public var description: String {
        var value = "\(MIDINote.description(for: Int(self.note)))(range: \(onset.formatted(.number.precision(.fractionLength(2)))) - \(offset.formatted(.number.precision(.fractionLength(2)))), note: \(self.note), velocity: \(self.velocity)"
        if self.channel != 0 {
            value += ", channel: \(self.channel)"
        }
        if self.releaseVelocity != 0 {
            value += ", release: \(self.releaseVelocity)"
        }
        
        return value + ")"
    }
    
}
