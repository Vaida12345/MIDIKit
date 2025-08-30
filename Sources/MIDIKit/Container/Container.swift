//
//  Container.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

import Foundation
import System
import AudioToolbox
import DetailedDescription
import FinderItem


/// A Container for MIDI Events.
///
/// - throws: ``OSStatusError``
public struct MIDIContainer: CustomStringConvertible, DetailedStringConvertible, Sendable, Equatable {
    
    public var tracks: [MIDITrack]
    
    public var tempo: MIDITempoTrack
    
    
    /// Creates a fresh container.
    ///
    /// - SeeAlso: For the default time signature and tempo, see ``MIDITempoTrack/init(events:tempos:)``.
    @inlinable
    public init(tracks: [MIDITrack] = [], tempo: MIDITempoTrack = MIDITempoTrack()) {
        self.tracks = tracks
        self.tempo = tempo
    }
    
    
    @inlinable
    public var description: String {
        self.detailedDescription
    }
    
    @inlinable
    public func detailedDescription(using descriptor: DetailedDescription.Descriptor<MIDIContainer>) -> any DescriptionBlockProtocol {
        descriptor.container {
            descriptor.sequence(for: \.tracks)
            descriptor.value(for: \.tempo)
        }
    }
    
}
