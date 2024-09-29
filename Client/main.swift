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


var container = try MIDIContainer(at: "/Users/vaida/Desktop/MIDIs/16 Regret : Humiliation.mid")

let tempos: [MIDITempoTrack.Tempo] = [.init(timestamp: 0, tempo: 300), .init(timestamp: 10, tempo: 10)]
container.adjustMIDINotesToVariadicTempo(tempos, currentTempo: 120)

/*
 │        │ ├─[0]: Note(range: 1.03 - 1.92, note: 54, velocity: 40)
 │        │ ├─[1]: Note(range: 1.50 - 2.22, note: 61, velocity: 60)
 │        │ ├─[2]: Note(range: 1.94 - 2.62, note: 54, velocity: 49)
 │        │ ├─[3]: Note(range: 2.24 - 2.94, note: 61, velocity: 64)
 */

detailedPrint(container)

try container.writeData(to: .desktopDirectory.appending(path: "vardic tempo.mid"))


//func scaledTime(at timestamp: MusicTimeStamp, tempoEvents: [MIDITempoTrack.Tempo], constantTempo: Double) -> MusicTimeStamp {
//    var lastTempoChangeTime: MusicTimeStamp = 0
//    var lastTempo: Double = tempoEvents.first?.tempo ?? constantTempo
//    var scaledTime: MusicTimeStamp = 0
//    
//    for tempoEvent in tempoEvents {
//        if timestamp < tempoEvent.timestamp {
//            break
//        }
//        
//        let timeDifference = tempoEvent.timestamp - lastTempoChangeTime
//        let scaledTimeSegment = timeDifference * constantTempo / lastTempo
//        scaledTime += scaledTimeSegment
//        
//        lastTempoChangeTime = tempoEvent.timestamp
//        lastTempo = tempoEvent.tempo
//    }
//    
//    // Scale remaining time up to the note's timestamp
//    let remainingTime = timestamp - lastTempoChangeTime
//    scaledTime += remainingTime * constantTempo / lastTempo
//    
//    return scaledTime
//    }
