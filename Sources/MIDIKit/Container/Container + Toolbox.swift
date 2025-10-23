//
//  Container + MusicSequence.swift
//  MIDIKit
//
//  Created by Vaida on 2025-06-10.
//

import AudioToolbox
import OSLog


extension MIDIContainer {
    
    public func makeSequence() throws -> MusicSequence {
        var sequence: MusicSequence!
        try withErrorCaptured {
            NewMusicSequence(&sequence)
        }
        
        // tracks
        for track in tracks {
            track.makeTrack(sequence: sequence)
        }
        
        // tempos
        var tempoTrack: MusicTrack!
        try withErrorCaptured {
            MusicSequenceGetTempoTrack(sequence, &tempoTrack)
        }
        
        tempo.events.forEach { _, event in
            event.withUnsafePointer { pointer in
                _ = MusicTrackNewMetaEvent(tempoTrack, event.timestamp, pointer)
            }
        }
        tempo.contents.forEach { _, tempo in
            MusicTrackNewExtendedTempoEvent(tempoTrack, tempo.timestamp, tempo.tempo)
        }
        
        return sequence
    }
    
    
    public init(sequence: MusicSequence) throws {
        defer { DisposeMusicSequence(sequence) }
        
        var count: UInt32 = 0
        try withErrorCaptured {
            MusicSequenceGetTrackCount(sequence, &count)
        }
        
        var midiTracks: [MIDITrack] = []
        
        struct AdditionalInfo {
            var tempos: [MIDITempoTrack.Tempo]
        }
        
        func processTrack(track: MusicTrack, additionalInfo: inout AdditionalInfo) throws -> MIDITrack? {
            var midiTrack = MIDITrack()
            
            var iterator: MusicEventIterator!
            try withErrorCaptured {
                NewMusicEventIterator(track, &iterator)
            }
            defer { DisposeMusicEventIterator(iterator) }
            
            var iteratorHasNextEvent: Bool {
                var bool = DarwinBoolean(false)
                MusicEventIteratorHasCurrentEvent(iterator, &bool)
                return bool.boolValue
            }
            
            var sustainOpen: Bool = false
            var sustainStart: MusicTimeStamp = 0
            var sustains: [MIDISustainEvent] = []
            
            while iteratorHasNextEvent {
                var dataPointer: UnsafeRawPointer?
                var dataSize: UInt32 = 0
                var timeStamp: MusicTimeStamp = 0
                var eventType: MusicEventType = kMusicEventType_NULL
                
                MusicEventIteratorGetEventInfo(iterator, &timeStamp, &eventType, &dataPointer, &dataSize)
                defer { MusicEventIteratorNextEvent(iterator) }
                guard let dataPointer else { continue }
                
                // The raw values, 0-10
                // kMusicEventType_NULL
                // kMusicEventType_ExtendedNote
                // ???
                // kMusicEventType_ExtendedTempo
                // kMusicEventType_User
                // kMusicEventType_Meta
                // kMusicEventType_MIDINoteMessage
                // kMusicEventType_MIDIChannelMessage
                // kMusicEventType_MIDIRawData
                // kMusicEventType_Parameter
                // kMusicEventType_AUPreset
                
                switch eventType {
                case kMusicEventType_MIDINoteMessage:
                    let event = dataPointer.bindMemory(to: MIDINoteMessage.self, capacity: 1).pointee
                    midiTrack.notes.append(MIDINote(onset: timeStamp, message: event))
                    
                case kMusicEventType_MIDIChannelMessage:
                    let event = dataPointer.bindMemory(to: MIDIChannelMessage.self, capacity: 1).pointee
                    guard event.status == 0xB0 && event.data1 == 64 else { break } // ensure is sustain
                    if event.data2 == 127 {
                        sustainOpen = true
                        sustainStart = timeStamp
                    } else if sustainOpen {
                        sustains.append(MIDITrack.SustainEvent(onset: sustainStart, offset: timeStamp))
                    }
                    
                case kMusicEventType_Meta:
                    let event = dataPointer.bindMemory(to: AudioToolbox.MIDIMetaEvent.self, capacity: 1).pointee
                    let data = Data(bytes: dataPointer + 8, count: Int(event.dataLength))
                    
                    midiTrack.metaEvents.append(.init(timestamp: timeStamp, type: event.metaEventType, data: data))
                    
                case kMusicEventType_ExtendedTempo:
                    let tempo = dataPointer.load(as: Double.self)
                    additionalInfo.tempos.append(MIDITempoTrack.Tempo(timestamp: timeStamp, tempo: tempo))
                    
                case kMusicEventType_MIDIRawData:
                    let event = dataPointer.bindMemory(to: AudioToolbox.MIDIRawData.self, capacity: 1).pointee
                    let data = Data(bytes: dataPointer + 4, count: Int(event.length))
                    midiTrack.rawData.append(MIDIRawData(data: data))
                    
                default:
                    let logger = Logger(subsystem: "MIDIKit", category: "MIDIContainer.init")
                    logger.warning("Unhandled MIDIEventType: \(eventType)")
                    continue
                }
            }
            midiTrack.sustains = MIDISustainEvents(sustains)
            
            return midiTrack
        }
        
        for i in 0..<count {
            var track: MusicTrack?
            MusicSequenceGetIndTrack(sequence, i, &track)
            guard let track else { continue }
            
            var additionInfo = AdditionalInfo(tempos: [])
            guard let midiTrack = try processTrack(track: track, additionalInfo: &additionInfo) else { continue }
            midiTracks.append(midiTrack)
        }
        
        var tempoTrack: MusicTrack?
        MusicSequenceGetTempoTrack(sequence, &tempoTrack)
        var additionInfo = AdditionalInfo(tempos: [])
        let midiTempoTrack = try processTrack(track: tempoTrack!, additionalInfo: &additionInfo)
        
        self.init(tracks: midiTracks, tempo: .init(events: midiTempoTrack!.metaEvents, tempos: additionInfo.tempos))
    }
    
}
