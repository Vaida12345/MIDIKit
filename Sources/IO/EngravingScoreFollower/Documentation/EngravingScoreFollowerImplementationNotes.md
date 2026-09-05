# EngravingScoreFollower implementation and verification

The behavioral authority is `EngravingScoreFollowerFinalDeliverable.md`. These notes describe
the implementation and host integration; they do not introduce another behavioral contract.
Hard reset and reference replacement clear visibility, as confirmed during implementation planning.

## Components and evidence

`EngravingScoreIndex` owns all score-sized storage. Ownership follows measure membership and
score order, including final-endpoint tolerance and nonconsecutive identifiers. It compiles
audible/lane masks, note durations, lane adjacency and gaps, register motion, short context
families, occurrence postings, interval-union queries, and normalized transition envelopes
for repeated monophonic material. Preprocessing may visit the whole score; consumption does not.

`EngravingInputState` assigns attack identities, normalizes velocity-zero attacks, and tracks
physical keys separately from sustain/sostenuto persistence. Reattacks remain attacks. Unknown
releases are neutral; duration evidence is withheld for ambiguous reattacks or unknown/active
pedals. Host ticks use `mach_timebase_info`; invalid comparisons never subtract unsigned times.

`EngravingFilter` keeps weighted alternatives for onset coverage, insertion, restrike, relevant
successors, omissions, trailing hands, participation changes, and change points. Hand modes
have normalized priors, and pitch emissions are categorical distributions over the expected
audible pitches. Timing modifies normalized transition rows, with a broad contamination floor.
Each path has its own tempo; shared spread calibration learns only from supported local paths.

New episodes use the same preceding evidence scale as continuity. They never inherit another
episode's onset count. Several change-point ages can agree on a destination: commitment
marginalizes them, then assigns a common continuity identity while preserving their separate
coverage, timing, and corroboration states. The competing incumbent remains separate during
relocation. Noise-prefix length is therefore not mistaken for destination ambiguity.

Pruned mass remains in bounded residual groups. Groups retain conservative reachable ranges,
known onset coverage, episode/coherence information, and lower bounds on corroboration. The
next event separates insertion mass from descendants that actually explain its pitch. Indexed
queries and transition envelopes tighten those groups. A still-private acquisition prefix can
be replayed with a retrieval focus derived from a distinguishing attack, within the current
event's remaining budgets; the focus is discarded after replay. All excluded occurrences
return as residual mass, so retrieval order cannot create uniqueness.

For a proposition such as “the current beat is d,” represented mass is a lower contribution and
residual mass an upper contribution. Residual groups that could oppose the proposition enter
the denominator at their upper bound. A group known entirely to support that same proposition
cannot lower its probability; the conservative minimum uses zero for that group's unknown
nonnegative mass. This distinction allows exact position to become supported while earlier
episode history remains ambiguous. It does not give an onset or jump certificate to a group
whose corroboration is unknown.

The small-score oracle runs the same transition model without pruning, retrieval truncation,
or work truncation and asserts zero residual mass. Monophonic and polyphonic tests compare
bounded destination support to that exhaustive distribution. This verifies the tested bounds
against the implemented model; it is not a claim of empirical probability calibration.

## Internal policy and resource parameters

The public thresholds are those in specification §10: 0.80 exact acquisition/local commitment,
0.90 tracking entry, 0.95 corroborated relocation, 0.98 ordinary movement, and 0.995 direct
reframing. Tracking hysteresis, the four-opportunity recent-fit window, two-onset relocation
floor, and 0.05 confidence-only publication granularity are implemented separately.

Initial likelihood parameters are engineering defaults: insertion mass 0.025, ordinary break
prior 0.001, lost break prior 0.04, acquisition noise-prefix renewal prior 0.12, and a geometrically
decreasing relevant-onset omission weight of 0.12. Block, roll, and hand-offset initial spread
scales are 45 ms, 200 ms, and 90 ms, with broad tails and robust adaptation. These scales are
likelihood parameters, never chord deadlines. No absolute tempo or quarter-note unit is assumed.
The initial large-omission presentation policy treats four or more omitted relevant attacks
starting outside the usable range as requiring a direct reframe, even across adjacent lines.
Omitting just the next line's first attack remains eligible for ordinary confirmed-entry advance.

The filter caps active paths at 128, detailed substates per destination at eight, new destination
evaluations at 64, detailed expansions at 4,096, event history at 256, and residual groups at 128.
Half the path slots reserve destination diversity across continuity and recovery; the remaining
slots retain high-mass hand/onset alternatives. Unused capacity is redistributed. Normal repair
examines up to eight score attacks; lost repair widens to sixteen within the same work budget.
Private acquisition replay uses at most sixteen retained events and shares the current consume
call's work and retrieval budgets. Physical state has exactly 128 pitch slots, and presentation
retains at most one pending intent. Coarse residual-envelope arithmetic is separately bounded by
these fixed capacities. Transient expansion buffers are also capped by the event work budget.

Bounds can remain loose in complicated repetitive/polyphonic material. The correct response is
to retain uncertainty and withhold uncertified movement. The tests include both false-certainty
safeguards and recovery/long-sequence checks; silence or withholding every action is not success.

## Host integration

Serialize reference installation, visibility reports, lifecycle calls, event consumption, and
processing of returned updates. Await installation before forwarding events for the new score.
Both consume overloads process the caller-selected stream as one performance; channels are not
hand labels. The follower contains no timer or asynchronous callback that publishes updates.

```swift
await follower.update(reference: completeMusicAndLayout)
follower.visibleRange = actualReadableBeatRange

// On the same serialized execution context:
if let update = follower.consume(inputEvent) {
    if update.viewportRevision != latestRevision {
        latestRevision = update.viewportRevision
        queuedRequest = nil  // Discard all older deferred authority.
    }
    drawMarkerOnlyIfDisplayed(update.displayBeat)
    switch update.viewport {
    case .unchanged:
        break
    case .advance, .jump:
        queuedRequest = HostRequest(
            navigationEpoch: navigationEpoch,
            revision: update.viewportRevision,
            action: update.viewport
        )
    }
}
```

`HostRequest`, marker drawing, and viewport execution above are host-owned pseudocode, not
additional MIDIKit input types. Before executing a deferred request, compare both its host
navigation epoch and its revision with the current values. Process earlier MIDI updates first.
Reveal an advance through the ordinary transition; reveal a jump directly. Clear the handled
request and report the actual readable range, including partial fulfillment or refusal.

Reporting visibility does not manufacture an `Update`. The next consume call publishes any
resulting cancellation revision. A request is never acknowledged by assuming the requested
geometry happened. Repeated unchanged reports and chord tones do not cause command storms.

For either reset, the host immediately increments its navigation epoch, discards queued requests,
clears the marker and latest revision, and calls the corresponding reset method. Automatic view
movement must not call `userReset()`. Hard reset clears visibility and calibration; navigation
reset retains broad calibration and provisional visibility while clearing position, hands,
physical certainty, timing anchors, and action authority.

Ignoring MIDI during a manual scrolling interval remains **deferred integration scope**. No
scrolling flag, timer, drag-completion inference, or caller-forwarding policy has been added.
Every event supplied to consume is processed. `userReset()` alone does not implement exclusion
of an interval and a subsequent attack does not prove that a drag ended.

## Scenario coverage and evaluation

The Swift Testing suites cover the specification's scenario groups as follows:

| Specification scenarios | Tests/coverage |
|---|---|
| Arbitrary/partial acquisition, initial noise | `distinctivePartialChordAcquiresBeforeCompletion`, `initialMistakesAndLocalOmissionsRecover` |
| Repetition, lookup truncation, distinguishing continuation | `truncatedRepeatedAcquisitionRecoversOnDistinguishingContinuation`, exhaustive comparisons, repeated-score measurements |
| Incomplete chords, late chord member after insertion, slow roll | `extraChordToneDoesNotPoisonLateMember`, parameterized serialization/roll traces |
| Missing attacks, local recovery, remote-looking errors | omission/recovery tests, `oneRemoteLookingCohortCannotJump`, `separateRemoteErrorsCannotAccumulateAJump` |
| Scored repetitions with/without releases | `scoredRepetitionsSurviveMissingReleases` |
| Leading/trailing and changing hands | `oneHandAndDelayedOtherHandDoNotDoubleAdvance`, `participationAdaptsWhenTheOtherLaneJoins` |
| Shared audible pitch and reference normalization | `canonicalSharedPitchIsOneAudibleAttack` |
| Legato, sustain, sostenuto | physical-state tests and `pedalOverlapDoesNotDelayProgress` |
| Invalid clocks, missing anchors, pauses | `timestampComparisonsArePairLocal`, `invalidTimestampsPreserveSequenceFollowing`, `pauseResumesLocally` |
| No silence/end prediction | final-attack, neutral-event, and no-anticipation tests |
| Visible replay and marker frontier | `visibleReplayHoldsMarkerUntilCatchup`, deferred-advance replay cancellation |
| Offscreen restart and current destination | `offscreenRestartRevealsCurrentCorroboratedBeat`, initial offscreen acquisition policy test |
| Empty lines versus omitted unread attacks | direct-reveal and destination-corroboration policy tests |
| Fully visible lines, clipped/sliver visibility | already-visible/clipping and sliver-readability policy tests |
| Entry confirmation, omitted first attack, delayed support | ordinary entry, omitted-first-onset, delayed-handoff, and already-received-entry resolution tests |
| Delayed/refused requests, partial fulfillment, revisions | pending-request, refusal, partial-fulfillment, uncertainty and replay cancellation tests |
| Hard/navigation/reference resets | fresh-start equivalence, calibration retention, physical-state and reference replacement tests |
| Unknown visibility, different wrapping, overload equivalence | invalid-visibility, conflicting-action, wrapping and overload tests |
| Determinism, output invariants, boundedness | deterministic replay, publication checks, long melody, burst stress and release measurements |

Controlled policy tests inject evidence at the policy boundary to test exact threshold and
request-lifecycle behavior independently of alignment tuning. End-to-end musical traces test
the complete façade. Ambiguous traces require holding until distinguishing evidence rather than
asserting a clairvoyant onset decision.

Run the engraving suites with `swift test --filter Engraving`; run release measurements with
`swift test -c release --filter EngravingPerformanceTests`. In the restricted development
environment, writable module caches and SwiftPM's `--disable-sandbox` option are needed to avoid
a nested sandbox failure. This does not require changing package dependencies or source files.

Release measurements report p50/p95/p99/max event latency, maximum path/residual/expansion counts,
and late synthetic commitments at 1,000 and 10,000 score moments. Timing limits are reported
rather than asserted against a particular CPU. No real timestamped pianist corpus is present in
this repository. Performer/score-separated evaluation, allocation profiling, confidence
calibration, reveal-latency distributions, and pianist disruption reports remain necessary
before making product reliability claims. Synthetic timings are not usability evidence.

## Verification results — 5 September 2026

The final optimized engraving run passed all **54 tests in five suites**. The debug package
regression run excluding `ScoreFollowerTests` passed **311 tests in 48 suites**. The unchanged
general-purpose `ScoreFollowerTests` suite reproduces **11 failures when run in isolation**;
neither its implementation nor its tests were modified. Consequently, a passing complete
package baseline has not been established, and the package-wide readiness condition remains
unmet. These failures are separate from the engraving suite results.

The final release stress run measured the following on this development machine. Each case
consumed 200 synthetic attacks; these are observations, not hardware-independent guarantees.

| Score moments | p50 | p95 | p99 | Maximum | Peak paths / residuals | Peak expansions | Late commitments |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1,000 | 1.084 ms | 1.163 ms | 1.179 ms | 1.189 ms | 128 / 128 | 2,354 | 0 / 200 |
| 10,000 | 1.218 ms | 1.310 ms | 1.373 ms | 1.464 ms | 128 / 128 | 2,432 | 1 / 200 |

The release command used writable caches and disabled debug-symbol generation to avoid the
environment's `dsymutil` permission failure:

```sh
CLANG_MODULE_CACHE_PATH=/tmp/midikit-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/midikit-swift-cache \
swift test --disable-sandbox --disable-automatic-resolution \
    -c release -debug-info-format none --filter Engraving
```

Bounded counts were checked; allocated bytes and allocation counts were not profiled. The
exhaustive comparisons cover the small synthetic scores in the tests and do not constitute a
general proof for every score. Real performance quality, confidence calibration, and the
remaining empirical measurements require the timestamped practice corpus described above.
