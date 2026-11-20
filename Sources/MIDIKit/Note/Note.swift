//
//  Note.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

import Foundation
import AudioToolbox
import SwiftUI
import Intervals


/// A MIDI note message.
///
/// `MIDINote`s are ordered by ``onset``, then by ``pitch``, so sorting notes gives the order they are played in, and notes played together from low to high. The remaining properties break any further tie, so that two notes are ordered unless they are equal.
public struct MIDINote: Sendable, Hashable, Interval, Comparable, BitwiseCopyable, Intervals::Interval {
    
    /// The onset, in beats.
    public var onset: MusicTimeStamp
    public var offset: MusicTimeStamp
    /// The key, as a MIDI note number: middle C is 60.
    public var pitch: UInt8
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
    
    /// The key, the same as ``pitch``.
    @available(*, deprecated, renamed: "pitch")
    @inlinable
    public var note: UInt8 {
        get { self.pitch }
        set { self.pitch = newValue }
    }
    
    /// Creates a note.
    ///
    /// - Parameters:
    ///   - onset: The time the note starts, in beats.
    ///   - offset: The time the note ends, in beats.
    ///   - pitch: The key, as a MIDI note number: middle C is 60.
    ///   - velocity: How hard the key is struck, in `1...127`.
    ///   - channel: The channel, in `0...15`.
    ///   - releaseVelocity: How fast the key is released.
    @inlinable
    public init(onset: MusicTimeStamp, offset: MusicTimeStamp, pitch: UInt8, velocity: UInt8, channel: UInt8 = 0, releaseVelocity: UInt8 = 0) {
        assert(channel <= 15)
        
        self.onset = onset
        self.offset = offset
        self.pitch = pitch
        self.velocity = velocity
        self.channel = channel
        self.releaseVelocity = releaseVelocity
    }
    
    @available(*, deprecated, renamed: "init(onset:offset:pitch:velocity:channel:releaseVelocity:)")
    @inlinable
    public init(onset: MusicTimeStamp, offset: MusicTimeStamp, note: UInt8, velocity: UInt8, channel: UInt8 = 0, releaseVelocity: UInt8 = 0) {
        self.init(onset: onset, offset: offset, pitch: note, velocity: velocity, channel: channel, releaseVelocity: releaseVelocity)
    }
    
    @inlinable
    internal init(onset: Double, message: MIDINoteMessage) {
        self.onset = onset
        self.offset = self.onset + Double(message.duration)
        self.pitch = message.note
        self.velocity = message.velocity
        self.channel = message.channel
        self.releaseVelocity = message.releaseVelocity
    }
    
    /// Orders notes by onset, then pitch, then offset, velocity, channel and release velocity.
    ///
    /// The order is total: two notes are either equal, or one comes before the other.
    public static func < (lhs: MIDINote, rhs: MIDINote) -> Bool {
        if lhs.onset != rhs.onset { return lhs.onset < rhs.onset }
        if lhs.pitch != rhs.pitch { return lhs.pitch < rhs.pitch }
        if lhs.offset != rhs.offset { return lhs.offset < rhs.offset }
        if lhs.velocity != rhs.velocity { return lhs.velocity < rhs.velocity }
        if lhs.channel != rhs.channel { return lhs.channel < rhs.channel }
        return lhs.releaseVelocity < rhs.releaseVelocity
    }
    
}


extension MIDINote: CustomStringConvertible {
    
    @inlinable
    public var description: String {
        var value = "\(MIDINote.description(for: Int(self.pitch)))(range: \(onset.formatted(.number.precision(.fractionLength(2)))) - \(offset.formatted(.number.precision(.fractionLength(2)))), note: \(self.pitch), velocity: \(self.velocity)"
        if self.channel != 0 {
            value += ", channel: \(self.channel)"
        }
        if self.releaseVelocity != 0 {
            value += ", release: \(self.releaseVelocity)"
        }
        
        return value + ")"
    }
    
}
