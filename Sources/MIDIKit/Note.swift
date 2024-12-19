//
//  Note.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

import Foundation
import AudioToolbox


public struct MIDINote: Sendable, Equatable {
    
    /// The onset, in beats.
    public var onset: MusicTimeStamp
    public var offset: MusicTimeStamp
    /// The key
    public var note: UInt8
    public var velocity: UInt8
    public var channel: UInt8
    public var releaseVelocity: UInt8
    
    /// The duration of the note, on set, it changes the ``offset``, while ``onset`` remains the same.
    public var duration: Double {
        get {
            self.offset - self.onset
        }
        set {
            self.offset = self.onset + newValue
        }
    }
    
    public init(onset: MusicTimeStamp, offset: MusicTimeStamp, note: UInt8, velocity: UInt8, channel: UInt8 = 0, releaseVelocity: UInt8 = 0) {
        self.onset = onset
        self.offset = offset
        self.note = note
        self.velocity = velocity
        self.channel = channel
        self.releaseVelocity = releaseVelocity
    }
    
    internal init(onset: Double, message: MIDINoteMessage) {
        self.onset = onset
        
        self.offset = self.onset + Double(message.duration)
        self.note = message.note
        self.velocity = message.velocity
        self.channel = message.channel
        self.releaseVelocity = message.releaseVelocity
    }
//    
//    public static func < (lhs: MIDINote, rhs: MIDINote) -> Bool {
//        lhs.onset < rhs.onset
//    }
//    
//    public static func <= (lhs: MIDINote, rhs: MIDINote) -> Bool {
//        lhs.onset <= rhs.onset
//    }
    
}


extension MIDINote: CustomStringConvertible {
    
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


extension MIDINote {
    
    /// The diatonic scale.
    ///
    /// To obtain a description of key, consider
    /// ```swift
    /// let (group, index, isSharp) = Keys.determine(note: 30) // 0-based index
    /// "\(Keys.diatonicScale[index])\(isSharp ? "#" : "")\(group - 1)"
    /// ```
    public static var diatonicScale: [String] {
        ["C", "D", "E", "F", "G", "A", "B"]
    }
    
    /// - Parameters:
    ///   - note: 0-based indexed note
    ///
    /// - Returns: 0-based indexed values.
    public static func determine(note: Int) -> (group: Int, index: Int, isSharp: Bool) {
        // layout [1, 1#, 2, 2#, 3, 4, 4#, 5, 5#, 6, 6#, 7], 12 in total
        //        [0, 1,  2, 3,  4, 5, 6,  7, 8,  9, 10, 11]
        
        let (group, index) = note.quotientAndRemainder(dividingBy: 12)
        
        let shiftedIndex: Int
        let isSharp: Bool
        
        switch index {
        case 0:
            isSharp = false
            shiftedIndex = 1
            
        case 1:
            isSharp = true
            shiftedIndex = 1
            
        case 2:
            isSharp = false
            shiftedIndex = 2
            
        case 3:
            isSharp = true
            shiftedIndex = 2
            
        case 4:
            isSharp = false
            shiftedIndex = 3
            
        case 5:
            isSharp = false
            shiftedIndex = 4
            
        case 6:
            isSharp = true
            shiftedIndex = 4
            
        case 7:
            isSharp = false
            shiftedIndex = 5
            
        case 8:
            isSharp = true
            shiftedIndex = 5
            
        case 9:
            isSharp = false
            shiftedIndex = 6
            
        case 10:
            isSharp = true
            shiftedIndex = 6
            
        case 11:
            isSharp = false
            shiftedIndex = 7
            
        default:
            fatalError("Invalid note index: \(index)")
        }
        
        return (group, shiftedIndex - 1, isSharp)
    }
    
    /// This project uses standard MIDI notation.
    ///
    /// - Middle C is MIDI note 60, labeled as C4.
    /// - Leftmost key: MIDI note 21 (A0).
    /// - Rightmost key: MIDI note 108 (C8).
    public static func description(for note: Int) -> String {
        let index = determine(note: note)
        return "\(MIDINote.diatonicScale[index.index])\(index.group - 1)\(index.isSharp ? "#" : "")"
    }
    
}
