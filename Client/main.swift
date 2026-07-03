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


//let container = try MIDIContainer(at: "/Users/vaida/Music/Piano Transcription/Owari no Sekai kara.mid")
//let asset = AVURLAsset(url: FinderItem(at: "/Users/vaida/Music/Music/Media.localized/Music/Animenz/Animenz Audios Full Version/Owari no Sekai kara.m4a").url, options: [AVURLAssetPreferPreciseDurationAndTimingKey : true])
//
//if #available(macOS 27.0, *) {
//    let session = try await MusicUnderstandingSession(asset: asset)
//    let results = try await session.analyze()
//    print(results.rhythm?.beatsPerMinute)
//    let view = DebugView(
//        container: container.indexed(),
//        downbeats: results.rhythm!.bars.map({ $0.seconds * 2 }),
//        beats: results.rhythm!.beats.map({ $0.seconds * 2 })
//    )
//    try view.render(to: .desktopDirectory/"file.pdf")
//}
#endif
