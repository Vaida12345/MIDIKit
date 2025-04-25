//
//  EqualizerParameters.swift
//  MIDIKit
//
//  Created by Vaida on 4/25/25.
//

import Foundation
import Observation


@Observable
public final class EqualizerParameters: Equatable {
    
    public var bands: [Band]
    
    public var globalGain: Float
    
    
    public func update(_ bands: Array<Band>, to engine: PianoEngine) {
        for (index, band) in bands.enumerated() {
            let eq = engine.equalizer?.bands[index]
            eq?.frequency = band.frequency
            eq?.bandwidth = 0.5
            eq?.gain = band.gain
            eq?.bypass = false
        }
    }
    
    public func update(_ globalGain: Float, to engine: PianoEngine) {
        engine.equalizer?.globalGain = globalGain
    }
    
    
    public init() {
        var bands = [
            Band(description: "32", frequency: 32),
            Band(description: "64", frequency: 64),
            Band(description: "125", frequency: 128),
            Band(description: "250", frequency: 256),
            Band(description: "500", frequency: 512),
            Band(description: "1K", frequency: 1024),
            Band(description: "2K", frequency: 2048),
            Band(description: "4K", frequency: 4096),
            Band(description: "8K", frequency: 8192),
            Band(description: "16K", frequency: 16384)
        ]
        
        for (index, band) in bands.enumerated() {
            let float = UserDefaults.standard.float(forKey: "EqualizerParameters.bands.\(band.description)")
            bands[index].gain = float
        }
        
        self.bands = bands
        
        self.globalGain = UserDefaults.standard.float(forKey: "EqualizerParameters.globalGain")
    }
    
    public static func == (_ lhs: EqualizerParameters, _ rhs: EqualizerParameters) -> Bool {
        lhs.bands == rhs.bands && lhs.globalGain == rhs.globalGain
    }
    
    
    public struct Band: Identifiable, Equatable {
        
        let description: String
        
        let frequency: Float
        
        var gain: Float = 0
        
        
        public var id: String {
            description
        }
    }
    
}
