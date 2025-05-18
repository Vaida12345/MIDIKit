//
//  DebugSustainLoss.swift
//  MIDIKit
//
//  Created by Vaida on 2025-05-17.
//

import SwiftUI
import MIDIKit
import Charts


struct DebugSustainLossView: View {
    
    let container: IndexedContainer
    
    
    var body: some View {
        let durations = container.sustains.map(\.duration)
        
        /// - Complexity: O(*n*).
        func loss(distances: [Double], reference: Double) -> Double {
            var i = 0
            var loss: Double = 0
            while i < distances.count {
                let remainder = distances[i].truncatingRemainder(dividingBy: reference)
                assert(remainder >= 0)
                loss += Swift.min(remainder, Swift.max(reference - remainder, 0))
                
                i &+= 1
            }
            
            return loss
        }
        
        let data = stride(from: 0.1, to: 10, by: 0.01).map {
            ($0, loss(distances: durations, reference: $0))
        }
        
        return Chart(data, id: \.0) {
            PointMark(
                x: .value("x", $0.0),
                y: .value("y", $0.1)
            )
        }
        .frame(width: 5000, height: 1000)
    }
}
