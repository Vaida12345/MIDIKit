//
//  Container.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

import Foundation
import AudioToolbox
import DetailedDescription


public struct MIDIContainer: CustomStringConvertible, CustomDetailedStringConvertible, Sendable {
    
    public var tracks: [MIDITrack]
    
    
    public func makeSequence() -> MusicSequence {
        var sequence: MusicSequence?
        NewMusicSequence(&sequence)
        guard let sequence else {
            fatalError()
        }
        
        for track in tracks {
            _ = track.makeTrack(sequence: sequence)
        }
        
        return sequence
    }
    
    public func writeData(to destination: URL) {
        MusicSequenceFileCreate(self.makeSequence(), destination as CFURL, .midiType, .eraseFile, 96)
    }
    
    public func data() -> Data {
        var data: Unmanaged<CFData>?
        MusicSequenceFileCreateData(self.makeSequence(), .midiType, .eraseFile, 96, &data)
        return data!.takeRetainedValue() as Data
    }
    
    
    public init(tracks: [MIDITrack] = []) {
        self.tracks = tracks
    }
    
    public init(at url: URL) throws {
        var sequence: MusicSequence?
        NewMusicSequence(&sequence)
        
        guard let sequence else {
            fatalError()
        }
        
        defer {
            DisposeMusicSequence(sequence)
        }
        
        let code = MusicSequenceFileLoad(sequence, url as CFURL, .midiType, .smf_PreserveTracks)
        guard code == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(code)) }
        
        let _count = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
        defer { _count.deallocate() }
        let _count_code = MusicSequenceGetTrackCount(sequence, _count)
        guard _count_code == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(_count_code)) }
        let count = _count.pointee
        
        var midiTracks: [MIDITrack] = []
        
        for i in 0..<count {
            var track: MusicTrack?
            MusicSequenceGetIndTrack(sequence, i, &track)
            guard let track else { continue }
            var midiTrack = MIDITrack()
            
            var iterator: MusicEventIterator?
            NewMusicEventIterator(track, &iterator)
            
            guard let iterator else { continue }
            
            var iteratorHasNextEvent: Bool {
                var bool = DarwinBoolean(false)
                MusicEventIteratorHasCurrentEvent(iterator, &bool)
                return bool.boolValue
            }
            
            var sustainOpen: Bool = false
            var sustainStart: MusicTimeStamp = 0
            
            while iteratorHasNextEvent {
                var dataPointer: UnsafeRawPointer?
                var dataSize: UInt32 = 0
                var timeStamp: MusicTimeStamp = 0
                var eventType: MusicEventType = kMusicEventType_NULL
                
                MusicEventIteratorGetEventInfo(iterator, &timeStamp, &eventType, &dataPointer, &dataSize)
                
                if let dataPointer {
                    switch eventType {
                    case kMusicEventType_MIDINoteMessage:
                        let event = dataPointer.bindMemory(to: MIDINoteMessage.self, capacity: 1).pointee
                        midiTrack.notes.append(MIDITrack.Note(onset: timeStamp, message: event))
                        
                    case kMusicEventType_MIDIChannelMessage:
                        let event = dataPointer.bindMemory(to: MIDIChannelMessage.self, capacity: 1).pointee
                        if event.status == 0xB0 && event.data1 == 64 {
                            if event.data2 == 127 {
                                sustainOpen = true
                                sustainStart = timeStamp
                            } else if event.data2 == 0 {
                                assert(sustainOpen)
                                midiTrack.sustains.append(MIDITrack.SustainEvent(onset: sustainStart, offset: timeStamp))
                            } else {
                                fatalError()
                            }
                        }
                        
                    case kMusicEventType_Meta:
                        let event = dataPointer.bindMemory(to: MIDIMetaEvent.self, capacity: 1).pointee
                        let data = Data(bytes: dataPointer + 8, count: Int(event.dataLength))
                        
                        midiTrack.metaEvents.append(.init(timestamp: timeStamp, event: event, data: data))
                        
                    default:
                        fatalError("Unhandled event: \(eventType)")
                    }
                }
                
                MusicEventIteratorNextEvent(iterator)
            }
            
            midiTracks.append(midiTrack)
            DisposeMusicEventIterator(iterator)
        }
        
        self.init(tracks: midiTracks)
    }
    
    
    public var description: String {
        self.detailedDescription
    }
    
    public func detailedDescription(using descriptor: DetailedDescription.Descriptor<MIDIContainer>) -> any DescriptionBlockProtocol {
        descriptor.container {
            descriptor.sequence(for: \.tracks)
        }
    }
    
}
