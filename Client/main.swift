//
//  main.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

#if os(macOS)
import FinderItem
import Foundation
import MIDIKit
import DetailedDescription
import SwiftUI
import AVFoundation
import MusicUnderstanding


let resultFolder: FinderItem = .desktopDirectory/"Results"
try resultFolder.makeDirectory()

let audioFolder: FinderItem = "/Users/vaida/Music/Music/Media.localized/Music"
let midiFolder: FinderItem = "/Users/vaida/Music/Piano Transcription"

let targets: [String] = ["Attack on Titan Main Theme"]

for target in targets {
    let midi = midiFolder/"\(target).mid"
    guard midi.exists else { continue }
    
    guard let audio = try audioFolder.children(range: .enumeration).first(where: { $0.isFile && $0.stem == target }) else {
        continue
    }
    
    print(audio)
    try! audio.startAccessingSecurityScopedResource()
    
    let container = try MIDIContainer(at: midi)
    let asset = AVURLAsset(url: audio.url)
    if #available(macOS 27.0, *) {
        let session = try await MusicUnderstandingSession(asset: asset)
        
        let result = try await session.analyze(for: [.rhythm])
        
        print(result.rhythm!.bars.map({ $0.seconds * 2 }))
        print(result.rhythm!.beats.map({ $0.seconds * 2 }))
        
        let view = DebugView(container: container.indexed(), downbeats: result.rhythm!.bars.map({ $0.seconds * 2 }), beats: result.rhythm!.beats.map({ $0.seconds * 2 }))
        try view.render(to: resultFolder/"\(target).pdf", format: .pdf)
    }
}
#endif
