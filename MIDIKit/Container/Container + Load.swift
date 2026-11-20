//
//  Extensions.swift
//  MIDIKit
//
//  Created by Vaida on 9/9/24.
//

import FinderItem


extension FinderItem.AsyncLoadableContent {
    
    /// Loads a MIDI file as a ``MIDIContainer``.
    public static var midiContainer: FinderItem.AsyncLoadableContent<MIDIKit.MIDIContainer, any Error> {
        .init { source in
            try MIDIKit.MIDIContainer(at: source)
        }
    }
    
    @available(*, deprecated, renamed: "midiContainer")
    public static var MIDIContainer: FinderItem.AsyncLoadableContent<MIDIKit.MIDIContainer, any Error> {
        midiContainer
    }
    
}
