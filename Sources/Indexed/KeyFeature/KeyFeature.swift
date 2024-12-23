//
//  KeyFeature.swift
//  MIDIKit
//
//  Created by Vaida on 12/24/24.
//


public struct KeyFeature {
    
    public let onset: Double
    
    public let keys: [UInt8 : Double]
    
    /// Duration in beats.
    public let duration: Double
    
    
    /// Calculate the similarity score, normalized between 0 and 1.
    ///
    /// - Returns: A vector of 12.
    public func similarity(to other: KeyFeature) -> [Double] {
        let score = ((0 as UInt8)..<12).map { i in
            let lhs = self.keys[i]
            let rhs = other.keys[i]
            
            if let lhs, let rhs {
                return 1 - abs(lhs - rhs)
            } else if lhs == rhs { // both nil
                return 1
            } else {
                return 0
            }
        }
        
        return score
    }
    
    init(onset: Double, keys: [UInt8 : Double], duration: Double) {
        self.onset = onset
        self.duration = duration
        var keys = keys
        for i in (0 as UInt8)..<12 {
            if keys[i] == 0 {
                keys.removeValue(forKey: i)
            }
        }
        self.keys = keys
    }
    
}
