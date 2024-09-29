//
//  Analytics.swift
//  MIDIKit
//
//  Created by Vaida on 9/10/24.
//

import SwiftUI
import Charts
import Accelerate


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
