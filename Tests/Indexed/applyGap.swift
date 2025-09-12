//
//  applyGap.swift
//  MIDIKit
//
//  Created by Vaida on 2025-09-12.
//

import Testing
import MIDIKit


@Suite
struct ApplyGapTests {
    
    @Test func main() async throws {
        let container = try MIDIContainer(at: "/Users/vaida/DataBase/Swift Package/Test Reference/MIDIKit/Ashes on The Fire.mid")
        try #require(container._checkConsistency())
        let indexed = container.indexed()
        await indexed.applyGap()
        #expect(indexed.makeContainer()._checkConsistency())
    }
    
}
