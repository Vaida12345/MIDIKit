# `EngravingScoreFollower` Maintainer Contract

This is the authoritative maintenance contract for the engraving follower. The longer-lived
implementation rationale is preserved in
[`EngravingScoreFollowerImplementationPlan.md`](EngravingScoreFollowerImplementationPlan.md).
`ScoreFollower` is a separate subsystem: do not route this feature through it or modify it as a
side effect.

## Product model

The follower serves a pianist reading an engraved score. A wrong marker is inconvenient; an
unexpected viewport movement can break reading and performance. Musical inference and visual
presentation therefore have distinct commitment rules.

```text
serialized MIDI
    → physical input state
    → bounded joint alignment filter
    → committed musical position
    → stable marker and viewport recommendation
```

The implementation is event driven. Silence alone cannot advance music. Calls must be serialized
in controller order; timestamps are evidence and are not a replacement for event order.

## Public API

- `update(reference:)` replaces the immutable music/layout reference and hard-resets all state,
  including performer calibration.
- `visibleRange` is the beat range actually usable in the UI. Before the first attack of an epoch
  it is a defeasible acquisition prior. During tracking it controls visible-replay classification
  and presentation only.
- `userReset()` is the sole navigation/reset signal. It accepts no arguments. Call it when the
  user begins scrolling, then keep publishing `visibleRange`. It clears position and partial-onset
  evidence, retains performer calibration, and detaches time across the interaction.
- `consume(_:)` and `consume(_:timestamp:)` preserve controller order and the original timestamp.
  Zero means temporal evidence is unavailable. Velocity-zero note-on is normalized to note-off
  without dropping its timestamp.

Before acquisition is reliable, `consume` returns `nil`. Acquisition is not a public tracking
state. Once acquired, `Update` contains:

- `beat`: committed musical position;
- `displayBeat`: stable primary marker;
- `measureIndex`: reference measure identifier;
- `confidence`: normalized probability of the published destination;
- `state`: `tracking`, `uncertain`, or `lost`;
- `activeHands`: inferred performed-hand participation;
- `viewport`: no movement, one-line advance, or direct jump;
- `didReframe`: true exactly when presentation changes spatial frame.

`plausibleBeatRange`, public `reset()`, `TrackingState.acquiring`, and `didRelocate` are not part of
the contract.

## Non-negotiable publication invariants

1. Ordinary committed continuity does not move `beat` backward.
2. Internal hypotheses may move anywhere; monotonicity is a publication rule, not an inference
   restriction.
3. Without `didReframe`, `displayBeat` cannot decrease.
4. Confirmed replay inside `visibleRange` may move `beat` backward, but holds `displayBeat` and the
   viewport until the performance catches its former frontier.
5. Uncertainty and lost tracking never move the viewport.
6. One anomalous performed onset cannot cause a visual reframe.
7. A nonlocal reframe requires a coherent post-change sequence and must dominate credible
   destinations.
8. Evidence before a possible restart is not destination history.
9. Ambiguous repeated destinations are not resolved by array, score, dictionary, or beam order.
10. Candidate truncation cannot manufacture a unique relocation.
11. A serialized chord cannot consume several score moments merely because its MIDI messages
    arrive separately.
12. Left-only, right-only, and both-hand practice need no mode selection. Cross-hand
    asynchrony must not advance the combined position twice.
13. Per-event work and retained state stay bounded with score length.

Assertions in presentation enforce the marker/reframe implications. Behavioral tests enforce the
remaining invariants.

## Compiled score

`EngravingScoreFeatureIndex` is immutable on the input path. It stores note-level hand and duration
data, pitch masks for three hand interpretations, measure/line ownership, hand-specific relevant
predecessors and successors, and pitch postings.

Indexed candidate generation unions bounded postings for all observed pitches. Do not replace
this with intersection or rarest-pitch selection: an accidental rare extra tone would exclude the
correct location. Exact matches may be used as a fast path. Every bounded lookup carries whether
unseen tied candidates may remain, and relocation must fail closed when they do.

Engraving line geometry must not influence musical continuity. It belongs only in acquisition
prior and presentation.

## Physical MIDI state

`PerformanceInputState` records depressed keys, attack and release times, re-articulation,
sustain, sostenuto, velocity, and controller event order. It does not construct chords. Key
release describes the physical controller even while a pedal sustains sound.

Do not reintroduce a global gesture timeout or greedy chord builder. The same attack may be an
extension under one alignment hypothesis and a new onset under another.

## Joint filter

`EngravingAlignmentModel` keeps a fixed-size log-probability beam. A hypothesis contains:

- score destination and hand interpretation;
- notes assigned to its current onset and unexpected notes;
- onset/attack timestamps;
- a path-local robust tempo clock;
- continuity versus new-episode identity;
- episode length, recent coherence, and lookup-exhaustion status.

For each note-on, each hypothesis considers the same onset, a same-onset hand reinterpretation,
the next relevant onset, bounded omissions, and—in parallel—indexed new-episode seeds. Equivalent
states are merged before deterministic pruning. Posterior confidence is aggregated by score
destination, not by raw path count; alternative hand and note-order paths are not independent
votes.

Pitch errors are penalized but survivable. Missing tones receive bounded penalties. A still
unplayed expected chord member strongly favors the same onset. A released repeated pitch and a
note expected by the next onset favor transition. If a note can belong to the other hand at the
current moment, same-onset reinterpretation competes against advancement.

Ordinary repair can absorb insertions and bounded omissions and must resume on the first strong
local observation. `lost` broadens the prior odds of indexed resumption; it does not switch to a
separate anchor algorithm.

## Timing and change points

Timing likelihoods are heavy-tailed and transition specific:

- within-onset attack intervals inform blocks versus rolls;
- inter-onset intervals update a smooth log-tempo path;
- releases provide weak note-duration/articulation evidence;
- a long break raises new-episode prior odds.

Invalid, equal, and nonmonotonic timestamp relationships are neutral. Timing never acts as a hard
pitch or chord gate. A pause never chooses a destination: the notes after it must still establish
coherent alignment. A pause followed by the expected local continuation remains local.

A restart hypothesis owns only evidence after its seed. Contradictory material breaks its coherent
run, so passage-like mistakes separated by local recovery cannot accumulate into a jump.

## Commitment and presentation

Acquisition needs either a sufficiently distinctive partial chord or a coherent sequence.
Visibility supplies prior probability but can be overcome by corroborated music. In a truncated,
repetitive lookup, several coherent visible observations are required.

Local forward motion commits at a lower threshold than relocation. A visible backward destination
uses replay. An offscreen or nonlocal destination uses jump only after at least three coherent
performed onsets and posterior dominance. Post-reframe hysteresis raises the cost of another
reframe but never makes recovery impossible.

`EngravingPresentationPolicy` owns all line behavior. It avoids movement if the next system is
already in `visibleRange`. Otherwise it emits one `.advance` at the last committed onset before the
next system is needed. An authorized offscreen jump emits `.jump` and sets `didReframe`. It cannot
promote an ordinary multi-line continuation into a jump by itself.

## Lifecycle and integration hazards

- User scroll: call `userReset()` once at scroll begin; publish ranges throughout the scroll.
- Follower-requested scroll: update `visibleRange`; do not call `userReset()`.
- Reference replacement: await `update(reference:)`; do not mix events from the old epoch.
- Send MIDI on one serialized executor. The follower is stateful and is not internally locking.
- Treat viewport recommendations as idempotent hints and report the resulting actual range.

## Required verification

Changes must retain tests for partial/wrong chords, extra near-simultaneous tones, omitted tones,
legato and pedals, repeated notes, slow rolls, asynchronous hands, changing hand participation,
tempo variation, pauses, replay, offscreen jumps, initial mistakes, invalid timestamps,
velocity-zero note-off, user navigation, repeated-score ambiguity, deterministic presentation,
and long-score boundedness. Run the focused follower suite, the complete package suite, and a
release build before delivery.
