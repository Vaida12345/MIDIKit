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


let folder: FinderItem = "/Volumes/Vaida's T9/Library/Machine Learning/Dataset/maestro-v3.0.0"
for file in try folder.children(range: .enumeration) {
    guard file.extension.contains("mid") else { continue }
    let container = try MIDIContainer(at: file)
    
    // check note offset is local
    let indexed = container.indexed()
}
#endif
