//
//  Extensions.swift
//  MIDIKit
//
//  Created by Vaida on 9/9/24.
//

import FinderItem


extension FinderItem.AsyncLoadableContent {
    
    public static var MIDIContainer: FinderItem.AsyncLoadableContent<MIDIContainer, any Error> {
        .init { source in
            try MIDIKit.MIDIContainer(at: source)
        }
    }
    
}
