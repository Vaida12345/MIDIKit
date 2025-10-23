//
//  Container + IO.swift
//  MIDIKit
//
//  Created by Vaida on 2025-06-10.
//

import AudioToolbox
import FinderItem


extension MIDIContainer {
    
    @inlinable
    @available(*, deprecated, renamed: "write(to:)")
    public func writeData(to destination: FinderItem) throws {
        try destination.removeIfExists()
        try withErrorCaptured {
            try MusicSequenceFileCreate(self.makeSequence(), destination.url as CFURL, .midiType, .eraseFile, .max)
        }
    }
    
    /// Writes the MIDI as file to `destination`.
    @inlinable
    public func write(to destination: FinderItem) throws {
#if DEBUG
        self._checkConsistency()
#endif
        
        try destination.removeIfExists()
        try withErrorCaptured {
            try MusicSequenceFileCreate(self.makeSequence(), destination.url as CFURL, .midiType, .eraseFile, .max)
        }
    }
    
    /// Obtain the MIDI data.
    @inlinable
    public func data() throws -> Data {
#if DEBUG
        self._checkConsistency()
#endif
        
        var data: Unmanaged<CFData>?
        try withErrorCaptured {
            try MusicSequenceFileCreateData(self.makeSequence(), .midiType, [], .max, &data)
        }
        return data!.takeRetainedValue() as Data
    }
    
    @inlinable
    public init(at source: FinderItem) throws {
        guard source.exists else { throw FinderItem.FileError(code: .cannotRead(reason: .noSuchFile), source: source) }
        
        var sequence: MusicSequence!
        try withErrorCaptured {
            NewMusicSequence(&sequence)
        }
        
        try withErrorCaptured {
            MusicSequenceFileLoad(sequence, source.url as CFURL, .midiType, .smf_PreserveTracks)
        }
        
        try self.init(sequence: sequence)
    }
    
    @inlinable
    public init(data: Data) throws {
        var sequence: MusicSequence!
        try withErrorCaptured {
            NewMusicSequence(&sequence)
        }
        
        try withErrorCaptured {
            MusicSequenceFileLoadData(sequence, data as CFData, .midiType, .smf_PreserveTracks)
        }
        
        try self.init(sequence: sequence)
    }
    
}
