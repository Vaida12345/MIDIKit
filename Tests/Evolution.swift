//
//  Evolution.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import Testing
import Foundation


extension Tag {

    /// Tests that measure how well an algorithm does, used while tuning it. They print their figures, and run only with ``Testing/Trait/evolution``.
    @Tag static var evolution: Self

}


extension Trait where Self == ConditionTrait {

    /// Disables a test unless the `MIDIKIT_EVOLUTION` environment variable is set.
    ///
    /// Use it with the ``Testing/Tag/evolution`` tag. To run the evolution tests:
    ///
    /// ```bash
    /// MIDIKIT_EVOLUTION=1 swift test
    /// ```
    static var evolution: Self {
        .enabled(if: ProcessInfo.processInfo.environment["MIDIKIT_EVOLUTION"] != nil, "Set MIDIKIT_EVOLUTION to run the evolution tests.")
    }

}
