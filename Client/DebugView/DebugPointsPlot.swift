//
//  DebugPointsPlot.swift
//  MIDIKit
//
//  Created by Vaida on 2025-05-18.
//

import SwiftUI
import MIDIKit
import Charts


struct DebugPointsPlot: View {
    
    
    var body: some View {
        func f(x: Double) -> Double {
            func unitNormalPDF(x: Double, mean: Double = 0, stdDev: Double = 1.5) -> Double {
                func f(x: Double) -> Double {
                    let exponent = -pow(x - mean, 2) / (2 * pow(stdDev, 2))
                    return (1.0 / (stdDev * sqrt(2 * .pi))) * exp(exponent)
                }
                
                return f(x: x) / f(x: mean)
            }

            
            return unitNormalPDF(x: x)
        }
        
        let data = stride(from: -4, to: 4, by: 0.01).map {
            ($0, f(x: $0))
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
