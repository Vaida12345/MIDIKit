//
//  DistributionView.swift
//  MIDIKit
//
//  Created by Vaida on 2025-06-10.
//

import SwiftUI
import Charts
import Accelerate
import MIDIKit
import FinderItem


public struct DistributionView: View {
    
    let value: [(Double, Int)]
    
    public var body: some View {
        Chart {
            ForEach(value, id: \.self.0) { (key, value) in
                BarMark(x: .value("range", key), y: .value("frequency", value))
            }
        }
    }
    
    public init(values: [Double], bins: Int = 1000, min: Double? = nil, max: Double? = nil) {
        let min = min ?? vDSP.minimum(values)
        let max = max ?? vDSP.maximum(values)
        
        let range = (max - min) / Double(bins)
        
        var results: [Double : Int] = [:]
        
        var i = 0
        while i < values.count {
            let _val = values[i]
            i &+= 1
            guard _val > min && _val < max else { continue }
            
            let value = (_val - min) / range
            results[Double(Int(value)) * range + min, default: 0] += 1
        }
        
        self.value = Array(results)
    }
}


#if os(macOS)
extension MIDINotes {
    /// Draw a histogram of the notes distances from direct previous notes.
    @MainActor public func drawDistanceDistribution(
        minimumNoteDistance: Double = Double(sign: .plus, exponent: -4, significand: 1)
    ) {
        let distances = [Double](unsafeUninitializedCapacity: self.contents.count - 1) { buffer, initializedCount in
            initializedCount = 0
            
            var i = 1
            while i < self.contents.count {
                let distance = self.contents[i].onset - self.contents[i-1].onset
                if distance >= minimumNoteDistance {
                    buffer[initializedCount] = distance
                    initializedCount &+= 1
                }
                
                i &+= 1
            }
        }
        
        DistributionView(values: distances)
            .frame(width: 800, height: 400)
            .render(to: FinderItem.desktopDirectory.appending(path: "frequency.pdf"))
    }
}
#endif
