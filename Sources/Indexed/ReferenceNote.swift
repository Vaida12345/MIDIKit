//
//  MIDINote.swift
//  MIDIKit
//
//  Created by Vaida on 12/19/24.
//

import Foundation
import AudioToolbox


public typealias ReferenceNote = UnsafeMutablePointer<MIDINote>


extension ReferenceNote: @retroactive CustomStringConvertible {
    
    public var description: String {
        self.pointee.description
    }
    
}

extension ReferenceNote: Interval {
    
    @inlinable
    public var onset: Double { self.pointee.onset }
    
    @inlinable
    public var offset: Double {
        get {
            self.pointee.offset
        }
        nonmutating set {
            self.pointee.offset = newValue
        }
    }
    
    @inlinable
    public var duration: Double {
        get {
            self.pointee.duration
        }
        nonmutating set {
            self.pointee.duration = newValue
        }
    }
    
    @inlinable
    public var note: UInt8 { self.pointee.note }
    
    @inlinable
    public var velocity: UInt8 {
        get {
            self.pointee.velocity
        }
        nonmutating set {
            self.pointee.velocity = newValue
        }
    }
    
    @inlinable
    public var channel: UInt8 {
        get {
            self.pointee.channel
        }
        nonmutating set {
            self.pointee.channel = newValue
        }
    }
    
    @inlinable
    public var releaseVelocity: UInt8 { self.pointee.releaseVelocity }
    
}
