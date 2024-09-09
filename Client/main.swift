//
//  main.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

import Stratum
import Foundation
import MIDIKit
import AudioToolbox
import DetailedDescription
import SwiftUI
import Charts
import Accelerate


//var container = try MIDIContainer(at: "/Users/vaida/Desktop/short.mid")
//var container = try MIDIContainer(at: "/Users/vaida/Music/Piano Transcription/16 Regret : Humiliation.mid")
var container = try MIDIContainer(at: "/Users/vaida/Music/Piano Transcription/Ashes on The Fire - Shingeki no Kyojin.mid")

//detailedPrint(container)

// lets deal with the leading 16 notes
var notes = MIDINotes(notes: Array(container.tracks[0].notes[0..<16]))

//// normalize durations
//notes.forEach { index, element in
//    element.duration = 0.01
//}

// demonstrate diff
print("The differences of onsets")
var prev: MIDINote? = nil
var gaps: [Double] = []
for note in container.tracks[0].notes {
    if let prev, note.onset - prev.onset > 1/16 {
//        print("\(note.onset - prev.onset, format: .number.precision(.fractionLength(3)))")
        gaps.append(note.onset - prev.onset)
    }
    
    prev = note
}

print(vDSP.mean(gaps) / 2)

let view1 = Distribution(values: gaps)
    .frame(width: 800, height: 400)
view1.render(to: FinderItem.desktopDirectory.appending(path: "frequency.pdf"))
let gapsMean = 0.2760505257716347

//container.tracks[0].quantize(by: gapsMean)
//
//try container.writeData(to: "/Users/vaida/Desktop/result.mid")
//
//detailedPrint(notes)

let min = vDSP.minimum(container.tracks[0].notes.map(\.onset))
// TODO: draw distribution graph of variations from the mean.
let view = Distribution(values: gaps.map({ note in
    note / gapsMean
}).filter({ $0 <= 3 }))
    .frame(width: 800, height: 400)
view.render(to: FinderItem.desktopDirectory.appending(path: "distribution.pdf"))

container.tracks[0].notes.deriveReferenceNoteLength()

// now, it is safe to assume that the scaling factor is `gapsMean`.

struct Distribution: View {
    
    let value: [(Double, Int)]
    
    var body: some View {
        Chart {
            ForEach(value, id: \.self.0) { (key, value) in
                BarMark(x: .value("range", key), y: .value("frequency", value))
            }
        }
    }
    
    init(values: [Double], bins: Int = 1000, min: Double? = nil, max: Double? = nil) {
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
