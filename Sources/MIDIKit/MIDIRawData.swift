//
//  MIDIRawData.swift
//  MIDIKit
//
//  Created by Vaida on 2025-10-23.
//

import Foundation
import AudioToolbox


/// A wrapper for raw data
///
/// - Important: MIDIKit does not write raw data when saving a MIDI. This structure is read-only.
public struct MIDIRawData: Sendable, Equatable {
    
    public let timestamp: MusicTimeStamp
    
    public let data: Data
    
    
    @inlinable
    public init(timestamp: MusicTimeStamp, data: Data) {
        self.timestamp = timestamp
        self.data = data
    }
    
    func withUnsafePointer<T>(body: (UnsafePointer<AudioToolbox.MIDIRawData>) throws -> T) rethrows -> T {
        let data = Swift.withUnsafePointer(to: UInt32(data.count)) { pointer in
            Data(bytes: pointer, count: 4)
        } + data

        return try data.withUnsafeBytes { pointer in
            try pointer.withMemoryRebound(to: AudioToolbox.MIDIRawData.self) { buffer in
                try body(buffer.baseAddress!)
            }
        }
    }
    
}


@available(macOS 13.0, *)
extension MIDIRawData: CustomStringConvertible {
    
    public var description: String {
        String(data: self.data, encoding: .utf8).map { "\"" + $0 + "\"" } ?? data.description
    }
    
}
