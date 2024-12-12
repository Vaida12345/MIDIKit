//
//  MIDI 2.0 Export.swift
//  MIDIKit
//
//  Created by Vaida on 12/6/24.
//

import Foundation


public struct MIDI2Exporter {
    
    let container: MIDIContainer
    
    
    public func makeData() -> Data {
        var data = Data()
        
        self.makeHeader(&data)
        
        return data
    }
    
    private func makeHeader(_ data: inout Data) {
        data.append("SMF2CLIP".data(using: .utf8)!)
    }
    
    public init(container: MIDIContainer) {
        self.container = container
    }
    
}
