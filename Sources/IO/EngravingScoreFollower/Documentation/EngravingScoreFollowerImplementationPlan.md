# `EngravingScoreFollower` Replacement Plan

This is the durable implementation plan for replacing the engraving follower's inference core.
It is intentionally independent of `ScoreFollower`, which must remain untouched.

## Target architecture

```text
serialized MIDI events
        -> physical input state
        -> bounded joint alignment filter
        -> musical commitment policy
        -> engraving presentation policy
```

The filter jointly infers score position, performed-onset membership, errors, hand participation,
tempo, and continuity versus a new performance episode. It must not irreversibly assemble a
physical gesture before alignment. There is no trusted-anchor recovery lane and no debug-only API
work in this replacement.

## Public contract

- `update(reference:)` installs a new immutable score/layout reference and performs a hard reset.
- `visibleRange` reports the actually usable score region and is never self-confirming musical
  evidence during established tracking.
- `userReset()` is the only public navigation/reset signal. It takes no arguments, begins a new
  acquisition epoch, clears positional and partial-onset evidence, retains performer calibration,
  and detaches timing across the scroll.
- `consume` preserves event order and the original MIDI timestamp. Zero, equal, and nonmonotonic
  timestamps retain pitch-only operation.
- `Update.beat` is a committed musical position. `Update.displayBeat` is the stable primary marker.
- `Update.didReframe` means presentation must change its spatial frame. It replaces the ambiguous
  `didRelocate` name.
- `plausibleBeatRange` is removed.
- `TrackingState` contains `tracking`, `uncertain`, and `lost`; acquisition remains private.

## Product invariants

1. Ordinary committed continuity never moves `beat` backward.
2. Internal hypotheses may move backward or elsewhere; monotonicity is a publication guarantee,
   not an inference restriction.
3. Without an authorized visual reframe, `displayBeat` never decreases.
4. A visible replay may move `beat` backward but never moves `displayBeat` or the viewport.
5. Uncertainty and lost tracking never move the viewport.
6. One anomalous performed onset cannot cause a viewport-changing jump.
7. Evidence before a possible restart cannot be scored as destination history.
8. Ambiguous repeated destinations are not resolved by score order, beam order, or lookup
   truncation.
9. Timing is transition-specific probabilistic evidence, never a hard chord or pitch gate.
10. One serialized chord cannot consume several score moments merely because its notes arrive as
    separate MIDI messages.
11. Left-only and right-only practice require no user selection, and cross-hand asynchrony must not
    advance the combined musical position twice.
12. Per-event work, retained hypotheses, and candidate retrieval stay bounded with score length.

## Implementation phases

### 1. Contract and evaluation fixtures

Rewrite the maintainer contract and integration guide around joint inference. Add trace fixtures
before tuning the replacement. Cover partial and wrong chords, omissions, legato overlap, pedals,
repeated notes, slow rolls, asynchronous hands, changing hand participation, tempo variation,
hesitation, replay, jumps, initial mistakes, invalid timestamps, and user scrolling.

### 2. Compiled score representation

Retain note-level durations, build hand-specific predecessors and motion features, and use
error-tolerant bounded candidate retrieval. Candidate generation must combine several observed
pitches so a rare extra pitch cannot exclude the correct location. Lookup truncation must retain an
explicit ambiguity risk.

### 3. Physical MIDI state

Track depressed keys, attacks, releases, sustain, sostenuto, event order, and timestamps without
deciding score-onset boundaries. Preserve the timestamp when velocity-zero note-on is normalized to
note-off.

### 4. Joint alignment filter

Maintain a bounded log-probability beam. Each hypothesis contains score position, within-onset
state, observed/missing/unexpected notes, hand interpretation, onset timestamps, tempo state,
continuity/new-episode identity, and accumulated probability. Note-on expansions include current
expected note, current insertion/substitution, re-articulation, next onset, bounded deletion, voice
reordering, and indexed restart proposals. Equivalent states are merged and pruning preserves
destination diversity.

### 5. Timing and change points

Use robust overlapping likelihoods for block chords, rolls, cross-hand offsets, inter-onset timing,
note dwell, insertions, and breaks. Tempo is a smooth latent state with uncertainty. A pause raises
the probability of a new episode but never chooses its destination. Silence alone does not advance
the score.

### 6. Acquisition, tracking, loss, and relocation

Acquisition accumulates imperfect partial evidence and uses visibility only as a defeasible prior.
Tracking state derives from posterior concentration and local-neighborhood mass. Lost tracking
widens bounded forward repair and indexed resumption proposals. Visible replay has a lower action
threshold than viewport-changing jump. A jump needs evidence from multiple performed onsets and
must dominate credible alternatives. Post-jump hysteresis raises reframe cost but never disables
recovery.

### 7. Commitment and presentation

Aggregate hypotheses by destination before publication. Separate local continuation, local
recovery, visible replay, and nonlocal jump. Confidence is normalized destination probability.
Engraving geometry affects presentation only. Use the actual visible range: avoid movement when the
next system is already visible, otherwise make one stable forward adjustment before it is needed;
use direct reframing for authorized nonlocal or multi-line movement.

### 8. Migration and verification

Remove the greedy gesture assembler, one-point incumbent, pending-skip repair, exact-mask
relocation certificate, mismatch-streak loss, and hard relocation disarming. Keep only one
production path. Validate real traces, randomized perturbations, presentation invariants,
deterministic replay, release-build latency, allocations, and long-score boundedness.

## Acceptance criteria

- An expected `1 3 5 7` onset played as near-simultaneous `1 3 5 6 7` remains one onset and does not
  block the following correct transition.
- Several ordinary mistakes followed by correct local playing recover locally, without waiting for
  a global jump.
- A distinctive partial chord can acquire; an initial wrong note does not poison acquisition.
- Confirmed visible replay separates `beat` from `displayBeat` without scrolling.
- A pause followed by local continuation remains local; a pause only changes restart probability.
- One anomalous onset never reframes the viewport.
- Offscreen relocation requires coherent multi-onset evidence and no credible competing
  destination.
- Zero and invalid timestamps preserve pitch-driven following.
- Event work and memory remain bounded on long repetitive scores.
- All presentation invariants hold and `ScoreFollower` is unchanged.
