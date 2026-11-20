//
//  Indexed+TimeWarp.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//


extension IndexedTrack {
    
    /// The fewest chords either track needs for the search. With fewer, the warp is the straight line through the first and the last chord.
    private static let minimumChordsToWarp = 8
    
    
    /// Returns the warp that maps the times of this track onto the times of `other`, which has the same piece.
    ///
    /// The typical pair is a sheet, whose notes are where they are written at a steady tempo, and a performance of it, which plays them at a tempo that wanders, pauses at a fermata, rolls chords, misses some notes and adds others. Both tracks may also have material the other lacks around the piece, such as the silence before the first note, a second playing, or applause. The result maps a time in beats of this track to the time in beats of `other` where the same notes sound. Use ``warped(by:)`` to apply it.
    ///
    /// The search reads onsets and keys only. Velocities, offsets, sustains and control events do not take part, as a transcriber does not report them faithfully. It works on the ``chords`` of the two tracks, each formed by its ``profile``, in these steps:
    ///
    /// 1. A rough alignment pairs the chords of the two tracks by the keys they hold alone, in the way of aligning two strings with gaps. It tolerates missing and extra chords and extra material at the ends, and finds repeated figures, but knows nothing about time.
    /// 2. A search through the states of a hidden tempo pairs the chords again in a band around the rough alignment. A pair earns what its chords share, and the way from one pair to the next costs gaps for the chords left out and a timing cost: how far the interval between the two performance chords is from the interval between the two sheet chords at the current tempo. The tempo may move by one of ``TimeWarp/Parameters/tempoBinCount`` states between pairs, so the tempo follows the playing instead of a straight line, and a pause is a stretch the timing cost does not grow over.
    /// 3. The paired chord times are fitted with a strictly increasing piecewise linear function: pairs at one time are merged, an isotonic regression repairs the order, and the Douglas-Peucker algorithm keeps the knots needed to stay within ``TimeWarp/Parameters/fitTolerance``.
    ///
    /// With fewer than 8 chords on a track, the result is the straight line through the first and the last chord. If either track has no chords, it is the ``TimeWarp/identity``, and if either has all its chords at one time, a shift that puts the first chord of this track on the first chord of `other`.
    ///
    /// - Parameters:
    ///   - other: The track to map onto, which has the same piece.
    ///   - parameters: The constants of the search. The default value is ``TimeWarp/Parameters/generic``. A track that came from a transcriber may have a preset of its own.
    ///
    /// - Returns: The warp from the beats of this track to the beats of `other`. To map the other way, call this on `other`.
    ///
    /// - Precondition: `parameters` are valid, see ``TimeWarp/Parameters/isValid``. Checked with a `precondition`.
    ///
    /// - Complexity: O(*n* · min(*m*, 4096)) for the rough alignment, and O(*m* · *w* · *b* · (*e* + 1)(*d* + 1) / 8) for the search, where *n* is the number of chords of this track, *m* the number of chords of `other`, *w* the width of the band, *b* the number of tempo states, *e* the largest number of extra chords and *d* the largest skip. For a piece with a few thousand chords on either track it takes a fraction of a second. The memory is at most 8,193 bytes for each chord of this track for the rough alignment, and 4 + 2 *b* bytes for each cell of the search's band whose two chords share a key, which is a few in ten, and the band stops widening at 256 MB of it. Forming the ``chords`` of both tracks on first use is not counted.
    public func timeWarp(to other: IndexedTrack, parameters: TimeWarp.Parameters = .generic) -> TimeWarp {
        precondition(parameters.isValid, "The parameters must be in the ranges their documentation requires.")
        
        let sheet = TimeWarp.Events(of: self)
        let performance = TimeWarp.Events(of: other)
        let n = sheet.count
        let m = performance.count
        guard n > 0, m > 0 else { return .identity }
        
        let sheetFirst = sheet.times[0]
        let sheetLast = sheet.times[n &- 1]
        let performanceFirst = performance.times[0]
        let performanceLast = performance.times[m &- 1]
        
        // A track whose chords are all at one time has no tempo to find: put the first chords onto each other.
        guard sheetLast > sheetFirst, performanceLast > performanceFirst else {
            return TimeWarp(validated: [TimeWarp.Knot(source: sheetFirst, target: performanceFirst)])
        }
        
        // All that a few chords tell is the line through the first and the last.
        let line = TimeWarp(validated: [
            TimeWarp.Knot(source: sheetFirst, target: performanceFirst),
            TimeWarp.Knot(source: sheetLast, target: performanceLast)
        ])
        guard n >= Self.minimumChordsToWarp, m >= Self.minimumChordsToWarp else { return line }
        
        let costs = TimeWarp.TempoCosts(parameters)
        let pilot = TimeWarp.pilot(sheet: sheet, performance: performance, scoring: costs.scoring)
        let centers = TimeWarp.bandCenters(pairs: pilot.pairs, sheetCount: n, performanceCount: m)
        let rate = (performanceLast - performanceFirst) / (sheetLast - sheetFirst)
        let alignment = TimeWarp.tempoSearch(sheet: sheet, performance: performance, rate: rate, costs: costs, centers: centers, halfWidth: parameters.bandHalfWidth)
        
        let anchors = TimeWarp.anchors(of: alignment.pairs, sheet: sheet, performance: performance)
        return TimeWarp.fit(anchors, tolerance: parameters.fitTolerance) ?? line
    }
    
}
