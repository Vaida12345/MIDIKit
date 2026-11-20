//
//  TimeWarp+Parameters.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//


extension TimeWarp {
    
    /// The constants of the search that ``IndexedTrack/timeWarp(to:parameters:)`` makes.
    ///
    /// The search pairs the chords of the two tracks. It scores a pair by the keys the two chords share, charges for the chords left without a partner, and charges for a timing that does not follow a smoothly changing tempo: the tempo is one of ``tempoBinCount`` states, and it may move one state between two paired chords. Times are in beats at 120 BPM, and costs are in the units of a match score, where one shared key is worth 2.
    ///
    /// Start from ``generic``, and change a single constant by copying it into a variable.
    public struct Parameters: Sendable, Hashable {
        
        /// The cost of each key of a chord that the chord it is paired with does not hold, which is the keys of either chord that are not shared.
        public var mismatchPenalty: Double
        
        /// The cost of the first chord of a run of chords that have no partner: a chord of the first track that the second track misses, or a chord of the second track that is extra.
        public var gapOpen: Double
        
        /// The cost of each further chord of such a run.
        public var gapExtend: Double
        
        /// The number of tempo states. It must be odd, and between 3 and 63. The middle state is the tempo that fits the two tracks' lengths, the others are faster and slower.
        public var tempoBinCount: Int
        
        /// The ratio between the tempos of two neighboring tempo states. It must be greater than 1.
        public var tempoBinRatio: Double
        
        /// The cost of moving the tempo by one state between two paired chords.
        public var tempoMoveCost: Double
        
        /// How unlikely a start tempo far from the middle state is: the cost is half the squared distance from the middle state, in the logarithm of the tempo, divided by this standard deviation squared. A restart after extra material draws the tempo the same way.
        public var tempoPriorSigma: Double
        
        /// The number of chords of the first track either side of the rough alignment that the search considers. The search widens the band, up to 1024, while its best path touches an edge.
        public var bandHalfWidth: Int
        
        /// The spread of the time between two paired chords, in beats, for a very short interval.
        public var timingNoise: Double
        
        /// The spread of that time as a share of the expected interval, which grows with the interval.
        public var relativeTimingNoise: Double
        
        /// How much a timing that is off counts, against the keys the chords share.
        public var timingWeight: Double
        
        /// The most that the squared deviation of a timing counts, half of it, before ``timingWeight`` applies. A pause or a fermata costs this and no more, instead of everything.
        public var timingCap: Double
        
        /// The cost of pairing two chords of the second track with one chord of the first, such as a chord whose notes are rolled far apart.
        public var splitCost: Double
        
        /// The time in beats over which the notes of a rolled chord may spread: the timing cost of such a pair is its time apart divided by this, up to ``timingCap``.
        public var rollScale: Double
        
        /// The largest step in chords of the first track between two paired chords. A step of *d* leaves *d* − 1 chords of the first track without a partner. It must be between 1 and 12.
        public var maximumSkip: Int
        
        /// The largest number of chords of the second track between two paired chords that have no partner. It must be between 0 and 12.
        public var maximumExtras: Int
        
        /// How far in beats the knots may stray from the times of the paired chords. A larger value gives fewer knots and a smoother warp.
        public var fitTolerance: Double
        
        
        /// Creates parameters with the given constants.
        ///
        /// See the properties of the same names for what each constant does, and for the range it must be in.
        public init(
            mismatchPenalty: Double,
            gapOpen: Double,
            gapExtend: Double,
            tempoBinCount: Int,
            tempoBinRatio: Double,
            tempoMoveCost: Double,
            tempoPriorSigma: Double,
            bandHalfWidth: Int,
            timingNoise: Double,
            relativeTimingNoise: Double,
            timingWeight: Double,
            timingCap: Double,
            splitCost: Double,
            rollScale: Double,
            maximumSkip: Int,
            maximumExtras: Int,
            fitTolerance: Double = 1/50
        ) {
            self.mismatchPenalty = mismatchPenalty
            self.gapOpen = gapOpen
            self.gapExtend = gapExtend
            self.tempoBinCount = tempoBinCount
            self.tempoBinRatio = tempoBinRatio
            self.tempoMoveCost = tempoMoveCost
            self.tempoPriorSigma = tempoPriorSigma
            self.bandHalfWidth = bandHalfWidth
            self.timingNoise = timingNoise
            self.relativeTimingNoise = relativeTimingNoise
            self.timingWeight = timingWeight
            self.timingCap = timingCap
            self.splitCost = splitCost
            self.rollScale = rollScale
            self.maximumSkip = maximumSkip
            self.maximumExtras = maximumExtras
            self.fitTolerance = fitTolerance
        }
        
        
        /// Whether every constant is in the range its documentation requires. ``IndexedTrack/timeWarp(to:parameters:)`` requires it.
        ///
        /// - Complexity: O(1)
        public var isValid: Bool {
            let nonNegative = [self.mismatchPenalty, self.gapOpen, self.gapExtend, self.tempoMoveCost, self.relativeTimingNoise, self.timingWeight, self.timingCap, self.splitCost, self.fitTolerance]
            let positive = [self.tempoPriorSigma, self.timingNoise, self.rollScale]
            return nonNegative.allSatisfy { $0.isFinite && $0 >= 0 }
                && positive.allSatisfy { $0.isFinite && $0 > 0 }
                && self.tempoBinRatio.isFinite && self.tempoBinRatio > 1
                && self.tempoBinCount >= 3 && self.tempoBinCount <= 63 && self.tempoBinCount & 1 == 1
                && self.bandHalfWidth >= 1
                && (1...12).contains(self.maximumSkip)
                && (0...12).contains(self.maximumExtras)
        }
        
        
        /// The parameters that assume nothing about where the notes came from.
        ///
        /// Tuned on about 200 pieces of the ASAP dataset, as the sheet, against the transcriptions of their MAESTRO recordings by transkun and by PianoTranscription, each cut to the performance and whole with the silence and extra material around it. The ground truth is the dataset's beat annotations, at the beats that have a chord of the sheet on them. On 211 other pieces, 96.5% of those beats fall within 50 ms of the truth for the cut recordings and 96.4% for the whole ones, 97.8% within 100 ms and 98.6% within 250 ms.
        ///
        /// The same constants serve every transcriber, as tuning per transcriber did not help. Constants tuned on the transkun transcriptions alone, and on the PianoTranscription transcriptions alone, beat these on neither: on held-out pieces, the differences were within ±0.1 points of the beats within 50 ms, 0 to 2 standard errors and mostly slightly negative, which is noise. These constants also score alike on both transcribers: on held-out pieces, 96.50%, 97.76% and 98.63% of the beats fall within 50, 100 and 250 ms for transkun, and 96.47%, 97.76% and 98.64% for PianoTranscription.
        public static let generic = Parameters(
            mismatchPenalty: 0.8,
            gapOpen: 1,
            gapExtend: 0.8,
            tempoBinCount: 21,
            tempoBinRatio: 1.35,
            tempoMoveCost: 0.6,
            tempoPriorSigma: 1.1,
            bandHalfWidth: 32,
            timingNoise: 0.08,
            relativeTimingNoise: 0.25,
            timingWeight: 0.5,
            timingCap: 6,
            splitCost: 0.5,
            rollScale: 0.08,
            maximumSkip: 6,
            maximumExtras: 3,
            fitTolerance: 1/50
        )
        
    }
    
}
