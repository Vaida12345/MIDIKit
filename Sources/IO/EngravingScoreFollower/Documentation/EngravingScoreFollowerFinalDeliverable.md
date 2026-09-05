# EngravingScrollFollower — behavioral specification

Revision 1, 5 September 2026. Consolidated design for review; implementation is not part of this deliverable.

This is the sole specification for the engraving follower. It supersedes the previous integration guide, agent contract, implementation plan, deliverable, and literature review. All behavior needed to implement the model is defined here; the linked papers explain evidence and limitations, not additional requirements. The user’s current requirements take precedence over earlier documents and the existing Swift stub.

The product is called **EngravingScrollFollower** in this document. Its existing Swift façade is **EngravingScoreFollower**; retain that type name unless the user requests a rename. The separate general-purpose **ScoreFollower** is outside this design’s scope.

**MUST** identifies an invariant. **Default** identifies a concrete initial policy that may be revised through evaluation without changing the invariant. User-confirmed choices and the explicitly deferred scrolling-state integration issue are recorded in §17; no unresolved capability is silently assumed.

## 1. Purpose, priorities, and limits

The follower recommends when an engraving view should reveal the line the pianist has demonstrably entered, so the pianist can continue without manual scrolling. Ordinary scrolling occurs on confirmed entry into that line, as explicitly chosen by the user. Its marker is secondary: it helps the pianist see and assess the follower’s estimate.

A piano performance is not an exact transcription of the reference. Normal input includes incomplete chords, wrong or extra notes, immediate corrections, omitted passages, repeated notes, short loops, structural repeats, asynchronous hands, one-hand practice, legato, pedals, rubato, and pauses. These are explanations the model must consider, not exceptions handled only after an exact matcher fails.

The model has three separate responsibilities:

1. Infer plausible score positions and explanations of the received performance.
2. Decide which musical position is sufficiently supported to publish.
3. Decide whether a viewport movement is justified and useful now.

An internally most likely position is not automatically a scroll instruction. Wrong jumps have a greater product cost than brief delays. Prolonged freezing also causes harm and must be measured separately; it is not success merely because nothing moved.

The aspiration is to scroll exactly when expected. The enforceable contract is more specific: preserve the reading frame when evidence is insufficient, reveal upcoming notation when both musical evidence and visual need justify it, and recover when distinguishing evidence arrives. Identical observed notes can represent continuation or a restart in an identical passage. MIDI does not reveal gaze, intention, or whether a reader has finished inspecting a line. No algorithm using these inputs can guarantee both zero unexpected movements and timely movement in every such case.

## 2. Invariants at a glance

1. Silence never advances the musical position or triggers a later scheduled scroll. This is an event-driven component.
2. Only an observed positive-velocity note-on can originate support for a new score attack. Releases and controls can refine existing explanations.
3. The model MUST keep competing explanations for onset membership, mistakes, position, hands, and timing. No irreversible global chord grouping precedes alignment.
4. A serialized chord MUST NOT acquire several onset confirmations merely because it contains several MIDI messages. Genuine ambiguity between a roll and successive notes remains uncertainty.
5. Exact chord completion, exact pitch masks, a mandatory hand, and a fixed chord timeout are never prerequisites for progress.
6. An observation explained only as a mistake supplies no positive progress/action evidence; one anomalous onset cannot authorize a new-episode viewport jump. Correct local continuation after mistakes can recover without first obtaining a global-jump certificate.
7. Long successful history supplies continuity preference; fresh evidence supplies permission to move. Old success cannot indefinitely excuse current mismatch.
8. A new episode uses only its own post-change observations as destination evidence. Unrelated mistakes cannot accumulate into a jump.
9. Repeated score occurrences remain separate positional alternatives. Candidate ordering, pruning, and lookup limits are not evidence of uniqueness.
10. Uncertain or lost public tracking holds the marker and viewport. Internal inference continues, including recovery proposals.
11. Musical progress, the stable marker, and viewport movement are distinct. A visible replay can change musical position without scrolling.
12. Visibility never reinforces an established musical hypothesis merely because the follower previously requested that view.
13. A requested viewport is not an observed viewport. Only current caller-reported visibility establishes what is actually readable.
14. Hard reset clears every mutable state, including learned calibration and visibility, while retaining the score. Manual navigation preserves only information safe to carry across that interaction.
15. Reference preprocessing/storage may scale with score size. Mutable inference state and candidate evaluations per event have fixed caps; no event performs a full-score scan.
16. No new public input is required by this design. Additional sensors or reference fields require consultation with the user before becoming requirements.
17. Ordinary scrolling MUST NOT precede confirmed entry into the target line. Neither the previous line’s final onset, predicted tempo, elapsed time, nor estimated visual look-ahead authorizes it. Once entry and the action gate are confirmed and movement is needed, emit the recommendation on that consume call without an additional dwell delay.

## 3. Inputs and score semantics

### 3.1 Available reference

The existing immutable EngravingReference contains:

| Element | Existing information | Interpretation |
|---|---|---|
| Note | MIDI pitch, written duration, left/right hand label | An expected attack, its notated extent, and an intended score lane |
| Moment | Beat, nonempty note collection, block/rolled attack | Notes notated to begin together; performance simultaneity is uncertain |
| Measure | Identifier, onset, duration | Musical ownership and a score-relative unit for presentation policy |
| Line | Identifier, beat range, measure-identifier range | Engraving system ownership and presentation destination |

All beat coordinates and durations use the same reference unit. Do not assume that one unit is a quarter note or infer a time signature. Measure and line identifiers are labels; the next line is the next line in score order, not identifier plus one.

Moments represent attacks, not all notes currently sounding. A held or tied continuation must not be supplied as a new attack unless a reattack is intended. The reference has no tie or ornament graph with which the follower could correct that encoding. Zero-duration notes are allowed; they still provide pitch/attack evidence, but no useful dwell-time expectation.

The current reference normalizes near-equal onset beats, merges their notes, retains the longest duration for duplicate pitch/hand pairs, and marks a merged moment rolled if any constituent is rolled. The follower uses this canonical result. If the same pitch appears in both hand labels, one physical piano-key attack must not be counted as two independent observations. It can satisfy the shared audible pitch while hand identity remains uncertain.

Measure ownership at a shared boundary belongs to the measure beginning there. A moment at the final score endpoint belongs to the final measure, consistent with the existing reference’s endpoint tolerance. In gaps, a moment must still belong to an actual measure under reference validation. Line ownership is obtained from that measure’s unique line membership. Do not select the first line whose closed beat range contains the moment: existing line beat ranges can overlap or overhang their measures.

Missing attacks in a measure or line do not make it musically discontinuous. A large beat gap describes absence of reference attacks, possibly while earlier notes sustain; it is not proof of a rest, fermata, or performer stop. Notes may continue across measure/line boundaries.

### 3.2 Derived information, requiring no additional input

The score model retains per-note durations and derives:

- Unique absolute pitch sets for both hands and each hand separately.
- Hand-specific predecessors/successors, beat gaps, register extrema, and coarse melodic/bass interval motion.
- Short ordered pitch/rhythm fingerprints, with absolute register retained alongside interval descriptions.
- Pitch and short-pattern occurrence frequencies; repeated-occurrence families and their distinguishing continuations.
- Measure ownership, line ownership, score-ordered lines, and attacks needed around a visual boundary.

These are deterministic descriptions of supplied data, not inferred ground truth about voices or intention. Register does not identify the physical hand; hands cross. Re-engraving the same music must not change established musical transition likelihoods. Geometry affects acquisition priors and presentation only.

The reference does not provide explicit voices, fingering, dynamics, repeat signs, voltas, D.C./D.S./coda instructions, gaze, screen geometry, a target tempo, or a reference recording. The model MUST NOT invent these inputs. It follows performed repeats after hearing evidence; it cannot anticipate a repeat from a notation graph it does not have. Unencoded ornaments are handled as imperfect observations, without claiming ornament-specific recognition.

### 3.3 MIDI observations

The musical observation is a serialized stream of pitch/velocity attacks, releases, control changes, and original Core MIDI host timestamps. The decoded overload carries no channel identity, and the wrapper’s channel is not a hand label. Both consume forms treat the selected input stream as one piano performance; the caller selects/routes that performance.

Normalize velocity-zero note-on to note-off while retaining its timestamp. A nonzero-velocity attack remains an attack even if its preceding note-off was lost. Do not deduplicate equal-pitch/equal-time messages on speculation about transport duplication: the API supplies no identity proving duplication. Instead retain rearticulation, duplicate/noise, and score-repetition explanations with capped evidence.

Track depressed keys separately from potentially sounding notes. Sustain (CC64) and sostenuto (CC66) affect sounding persistence; they never manufacture attacks, complete a chord, or postpone recognition until pedal-up. Sostenuto concerns notes held when it is engaged. Missing pedal information removes this evidence without disabling following. Velocity is not a required alignment feature and does not identify a hand. Other controls are musically neutral; channel-mode key/pedal cleanup, where supported, supplies no positional evidence.

Releases attach to physical pitch state, not a global current chord. Unknown/unmatched releases are harmless. Reattack or missing-message ambiguity weakens duration evidence rather than creating impossible physical certainty.

## 4. Public lifecycle and outputs

### 4.1 The five operations

| Operation | Required behavior |
|---|---|
| update(reference:) | Atomically install the complete score/layout reference and compiled features; perform a hard reset against that reference |
| visibleRange | Read/write the actually usable beat range; update presentation knowledge and, during acquisition only, the acquisition hint |
| userReset() | Begin a new navigation/acquisition epoch; revoke positional and viewport authority, retaining safe performer/physical information |
| reset() | Hard reset; retain the installed immutable reference/index and clear all mutable state |
| consume | Consume one serialized MIDI event with its original timestamp and return an optional Update |

Construction without a reference is allowed. Until a reference and reliable acquisition exist, consume returns nil. Do not extrapolate a position from the first score measure. The two existing consume overloads are representations of the same operation, not different algorithms. No extra required input, timer, acquisition mode selector, or public plausible-range API is introduced.

Callers serialize lifecycle operations, visibility reports, and MIDI consumption. Await reference installation before delivering its events. Old-epoch MIDI and delayed old-layout visibility must not cross installation/navigation boundaries. Timestamps are evidence, not permission to reorder events. The existing async installation surface may be retained; it must never expose partly installed music/layout.

### 4.2 Reset contents

| State | Hard reset / reference replacement | userReset |
|---|---|---|
| Installed reference and its derived indexes | Retain / replace atomically | Retain |
| Published beat, marker frontier, last update | Clear | Clear |
| Continuous paths, replay/restart evidence, onset assignments | Clear | Clear |
| Pending viewport request, output revision, and movement hysteresis | Clear | Clear; caller discards previous navigation-epoch requests |
| visibleRange | Clear; await a fresh report | Retain latest report provisionally; accept subsequent reports |
| Beat/time phase, episode tempo, timestamp interval anchors | Clear | Clear; never time across navigation |
| Current hand-participation certainty | Clear | Clear |
| Learned chord spread, hand-offset variability, articulation/error tendencies | Clear | Retain broad, robust distributions and sample support |
| Learned absolute tempo | Clear | At most a broad initialization prior, never an active beat clock |
| Known depressed-key/pedal facts | Clear to unknown | Clear to unknown; ignored input during navigation could otherwise leave stale held keys or pedals |

This soft reset deliberately retains reusable performer calibration, rather than keeping a possibly wrong score location as an anchor. Pre-navigation held notes cannot reacquire a position or count as new-episode evidence. A fresh attack is necessary. Post-navigation pedal/release evidence remains uncertain until refreshed; unknown physical state cannot veto new notes.

The caller clears/hides its old marker when it initiates either reset; a void reset does not emit an Update. Automatic movements requested by the follower must never call userReset.

### 4.3 Update

The design retains the useful existing diagnostic fields and fixes their meaning:

| Field | Meaning |
|---|---|
| beat | Committed score-moment beat, never a free-running clock prediction |
| displayBeat | Stable decorative marker, governed by §12 |
| measureIndex | Owner of beat, not necessarily owner of the held displayBeat |
| confidence | Conservative model support for the exact published beat, after marginalizing latent substates and accounting for unexamined alternatives (§9) |
| state | tracking, uncertain, or lost; acquisition remains private |
| activeHands | unknown, left, right, or both; inferred score-lane participation with hysteresis |
| viewport | unchanged, advance(toLine:), or jump(toLine:) |
| viewportRevision | Epoch-local revision of viewport authority; changes on a new request or cancellation so the host can discard obsolete deferred requests (§13.5) |
| didReframe | True exactly when this Update contains jump; it describes a recommendation, not acknowledgment that the view moved |

Before initial acquisition, return nil. Afterwards, return an Update when committed position, display position, state, hand participation, a material confidence change, or viewport authority changes. A cancellation returns an Update even if beat and displayBeat stay the same. Default confidence-only publication granularity is 0.05 absolute; state and authority changes are never suppressed by this granularity. The confidence value itself is not rounded for inference.

A recommendation is a one-time event in that Update, not a persistent command to replay from a cached snapshot. Later Updates return unchanged unless a new recommendation is authorized. Nil means no new public information, not permission to clear the last display or assume tracking failed.

Release/control events may revise confidence, state, or commitment concerning already observed attacks; they add no independent onset confirmation. Viewport decisions are normally made on note-on. If a release/control event supplies the final evidence resolving an already received entry attack and all action gates now pass, that consume call may emit the action. It cannot advance by itself through a rest or to an onset never attacked. Repeated controls or releases must not accumulate independent relocation evidence. This avoids an artificial extra wait after entry has actually been confirmed.

There is no end-of-performance signal. At the final attack, the follower may hold a valid tracking position. Silence does not imply lost or finished, and does not move the marker to the score’s final duration endpoint.

## 5. Joint interpretation of a performance

### 5.1 The model’s state

Maintain a bounded distribution over plausible explanations, rather than one mutable score index. Each explanation distinguishes:

- Score occurrence and current score-onset assignment.
- Which expected pitches have been attacked, unexpected attacks, and possible rearticulations.
- Coupled left/right attack positions, uncertain participation, and delayed/early hand assignments.
- Attack and release timing relationships; onset-spread versus between-onset timing.
- Episode identity, proposed change point, coherent post-change progress, and whether continuation or a restart explains the observation.
- Local tempo tendency and uncertainty, independently from shared performer calibration.
- Recent predictive fit and unresolved search/segmentation ambiguity.

A hierarchical probabilistic filter or equivalent weighted state model may realize this logic. The chosen representation must preserve meaningful alternatives until later evidence can distinguish them. It must not replace the model with an exact matcher plus unrelated jump, skip, and anchor heuristics.

### 5.2 Every attack has competing explanations

| Explanation | Supporting evidence | Counterevidence / restraint |
|---|---|---|
| Another pitch of the current onset | Previously unplayed expected pitch; compatible spread; delayed other hand | Strong ordered successor evidence; implausibly long accumulation without coherent onset fit |
| Extra/wrong note | Isolated unexpected pitch; nearby correct material; correction-like timing | Persistent structured continuation that fits another location better |
| Rearticulation of current note/chord | Repeated pitch; possible intervening release; no supported score progress | A scored repeated onset with compatible rhythm and following sequence |
| Next relevant onset | New score attacks, compatible beat/time progression, coherent hand path | Credible current-chord extension or hand-lag explanation |
| Forward omission recovery | Later nearby attack fits; skipped moments have a bounded omission cost | Arbitrarily long skips, fresh contradictions, competing repeated occurrences |
| Late/early other-hand attack | Compatible coupled hand lanes and performer offset distribution | Unbounded hand separation or reassignment chosen merely to excuse every error |
| Earlier history was misaligned | Reinterpretation of a bounded received suffix yields a coherent nearby path | Must not rewrite unseen future or treat old public guesses as observations |
| New replay/restart episode | Coherent ordered suffix at a competing occurrence; continuity predicts poorly | Single-cohort evidence, shared motifs, unexplained contradictions, hidden alternatives |

One observation is explained once within each hypothesis. It may support different alternatives, but it cannot be duplicated as several independent score attacks along one path. A transition can skip several omitted score moments and land on one observed destination; skipped moments are not performed confirmations.

### 5.3 Chords, errors, and anti-sticking behavior

Missing tones are charged when a hypothesis leaves or revises an onset, not repeatedly while the onset remains incomplete. Omission cost depends on inferred hand participation. Expected-note coverage has diminishing returns; ten notes in a chord do not count as ten independent episode observations.

An unexpected attack has a nonzero noise/insertion probability everywhere, with a finite penalty. A wrong note can combine insertion of the played pitch with omission of an expected pitch. Small pitch errors may receive a weak proximity preference, but exact register remains important: octave or chromatic similarity cannot erase positional distinctions.

Robustness must not make an onset an unlimited sink for all subsequent notes. Cap each anomalous observation’s damage, not the total cost of indefinitely explaining a passage as errors. Successive attacks that only fit through insertions worsen recent predictive fit. A clean local alternative starts with a fresh within-onset assignment and can win on the first sufficiently informative correct continuation. It retains the cost of the required omissions and cannot turn an arbitrary remote destination into a cheap local repair.

For expected pitches {60, 64, 67, 71}, a near-cohort performance 60, 64, 67, 70, 71 should normally remain one onset with one insertion. The late 71 remains available as an expected chord member after the extra 70. The next correct score onset must be able to advance without requiring a reset or jump.

That is an evidence-conditioned expectation, not an oracle guarantee. If the same messages are equally compatible with fast successive scored notes, retain that uncertainty. Avoid a false scroll until their interpretations diverge.

### 5.4 Hands and the published musical position

Left and right are coupled score lanes, not two unconstrained followers. Permit bounded early/late assignments across adjacent moments. The performance may contain either lane, both, or a gradual participation change without user selection.

Each hypothesis has a central progress frontier: the latest onset with a supported attack in its coherent forward episode. A trailing hand can finish an earlier onset without reversing or advancing that frontier. Two attacks at the same notated onset cannot advance it twice. A leading hand can propose the next frontier, but the same-onset/lagging alternatives still compete before commitment.

Publish beat only when sufficient mass supports that exact frontier. Never average two different occurrences or two hand beats into an unobserved intermediate beat. Maintain separately the earliest still-relevant active-hand passage for presentation; an early hand must not make the viewport remove the other hand’s currently needed notation. An inactive lane must not hold progress hostage to its missing notes.

Participation changes gradually with repeated credible assignments, with faster widening to unknown when observations disagree. Do not confidently select a new hand from one convenient pitch, and do not repeatedly switch hand interpretations to eliminate omission costs. Shared-pitch and crossing-hand ambiguities can leave activeHands unknown while musical following remains useful.

## 6. Timing and performer adaptation

### 6.1 Usable time

Input order is authoritative. Use the original host timestamp for physical intervals; callback arrival spacing is not performance rhythm. Convert host ticks through the platform’s actual host-time scale when applying absolute-time priors. Never hard-code raw ticks as milliseconds.

Zero, equal, decreasing, or otherwise unusable timestamp relationships supply no interval likelihood and no tempo update for that comparison. They retain pitch and sequence evidence. Do not subtract unsigned timestamps before checking order. Validity is pair-local: an equal-time chord member or untimestamped pedal message does not erase otherwise valid onset-to-onset anchor pairs. Across a missing attack timestamp, either detach the affected lane clock or compare explicit valid score-onset anchors using their full score-beat separation. Never pair a multi-onset elapsed interval with only the most recent one-onset beat gap. A detected clock discontinuity detaches all affected anchors; later valid observations can establish fresh ones.

An extreme positive interval has both a pause interpretation and a possible clock discontinuity interpretation. These cannot always be distinguished from this API. Downweight or detach the phase rather than assigning absurd tempo. Event-order following must still work.

### 6.2 Distinct timing processes

Use separate overlapping distributions for block-chord spread, rolled-chord spread, hand offsets, between-onset progression, corrections/rearticulation, and weak note dwell/articulation. Rolled metadata widens the roll explanation; it is not a deadline or a prescribed ascending pitch order. A block-marked chord may still be played with a spread.

The basic between-onset prediction is:

~~~text
expected time gap = positive score-beat gap × local seconds per score beat
~~~

Uncertainty includes tempo drift, beat gap, and expressive residual timing. Broad-tailed likelihoods allow rubato, slow practice, and hesitation. Within-onset intervals use both time since onset start and time since the preceding attack; this prevents an indefinitely extended chord made of individually short gaps.

Use credible corresponding onset anchors, or same-lane anchors, for tempo learning. Adjacent raw MIDI messages across hands are not necessarily adjacent musical beats. Never learn tempo from a chord’s internal serialization, backward assignment, zero beat distance, or elapsed time across an unconfirmed jump. Duration and note-off observations are weak: staccato, legato, missing releases, and pedals make written duration an unreliable physical key-down requirement.

### 6.3 Learning without self-reinforcement

Each candidate carries its own tempo estimate and uncertainty, including a restart candidate learning from its own post-change onsets before confirmation. Only the interval bridging the old episode to the new destination is excluded from that learning. Shared performer calibration learns gradually from repeatedly supported local alignments. Ambiguous assignments and remote proposals do not train the shared model as if confirmed. Retain broad floors on timing/error variability, limit the influence of any one episode, and reduce reliance when calibration is weak or a new passage disagrees.

A long pause increases the prior probability of a break; it does not choose a destination. A pause followed by the expected successor should normally resume locally with detached phase and widened tempo uncertainty. A pause followed by a distinct earlier passage can establish replay. Pauses are recognized when a subsequent event arrives; no hidden timer acts during silence.

## 7. History, change points, and recovery

### 7.1 Use history at two scales

Longer history establishes a prior over occurrence identity, continuity, performer tendencies, and tempo. Recent history tests whether that explanation still predicts the performance. These are different quantities. A lifetime match total is never sufficient evidence to advance now.

| Evidence pattern | Interpretation and required response |
|---|---|
| Good long history, one recent wrong note | Keep continuity credible; absorb an error; withhold action unsupported by the new event |
| Good long history, several incoherent recent attacks | Lower current trust, hold presentation, examine local repair and new episodes |
| Good long history, coherent recent match elsewhere | Compare a post-change episode with continuous repair; old success must not make recovery impossible |
| Weak old history, strong clean local continuation | Correct the local interpretation promptly; do not wait for global relocation confirmation |
| Recent passage matches several repeated occurrences | Preserve occurrence alternatives; a good absolute match is not a unique location |
| Remote-like mistake, correct local passage, another remote-like mistake | Local recovery breaks the earlier proposed remote run; do not combine the two mistakes into jump evidence |

Maintain a bounded revisable suffix of received observations. Revising that suffix can explain that a late chord member was really the next onset, or that an earlier transition was premature. It cannot retroactively make a viewport command safe. Output policy governs any resulting backward correction just as it governs replay.

### 7.2 Episodes

A restart proposal identifies a possible change point and a destination occurrence. It receives a low but nonzero prior during normal playing, increased when recent continuity predicts poorly or a break is plausible. Global proposals remain available while tracking; entering lost is not a prerequisite for recognizing a real repeat.

Compare episodes on a common observation history. Conceptually:

~~~text
episode support = probability of a break at its proposed change point
                × destination prior
                × likelihood of observations after that point at that destination
~~~

The preceding history informs the break prior and the competing continuation. It is not pasted before the proposed destination as a matching prefix. Raw log likelihoods from different-length suffixes cannot be compared without their corresponding change-point probabilities and common-history normalization.

A seeded episode must continue explaining subsequent events. It cannot erase each contradiction by resetting its seed while inheriting accumulated confirmation. A fresh seed starts fresh. Ordinary pitch mistakes may be absorbed with finite penalties, but an unexplained return to the incumbent passage invalidates the old coherent restart run.

### 7.3 Locality

Locality is a bounded musical neighborhood around the active path, measured through relevant score attacks and plausible omissions. It is not a number of engraved lines. Successor transitions across empty measures remain continuity. An expansion of the local window when lost does not reduce the visual authorization required for an offscreen correction.

Clean local recovery may update beat on the first sufficiently distinctive correct onset after mistakes. A return to an earlier beat requires confirmed correction/replay, even if the distance is small. Immediate restrikes need not be interpreted as backward movement at all.

### 7.4 Tracking quality

Tracking state is evaluated from destination/mode support, recent predictive likelihood, and unexplained-observation probability, not a fixed mismatch count.

- **tracking:** a coherent local path or compact local mode is supported by fresh observations. A compact mode means adjacent onset/hand-assignment ambiguity within the same continuous occurrence, never distant copies of a motif.
- **uncertain:** continuity remains plausible but current assignments or competing paths are unresolved enough that presentation movement is unsafe.
- **lost:** local predictive support has substantially collapsed, or the recent observations are mostly explained as unstructured errors rather than a coherent musical path.

A concentrated posterior can still be wrong when every available model predicts the data badly. Include an explicit unstructured/noise explanation or equivalent recent-fit diagnostic so normalized candidate dominance alone cannot claim tracking.

Lost broadens the bounded repair neighborhood, gives recovery candidates more of the fixed processing budget, and weakens the prior favoring the incumbent. It never lowers the minimum evidence required for a disruptive reframe. When a supported path recovers, the same event may change state to tracking and authorize an action; an Update marked uncertain or lost always has viewport unchanged.

## 8. Acquisition and repeated passages

### 8.1 Starting anywhere

After reset, acquisition searches across the score with a broad start prior. Valid visibility supplies a defeasible prior over the visible region. Normalize region mass before distributing it across candidates: a dense region must not receive more total prior merely because it has more moments. Default prior mass is 0.8 within a valid hinted region and 0.2 elsewhere when both contain candidates. If visibility is unknown or contains no candidate attacks, use the broad prior.

The first fresh attack samples the acquisition hint. If reported visibility changes before acquisition commits, refresh that hint for the still-private acquisition episode, replacing rather than multiplying the previous visual prior. Once acquired, visibility is no longer a musical prior. This prevents automatic scrolling from confirming itself.

A distinctive partial chord may acquire without completion. A single common note normally cannot. Initial mistakes may be explained as a bounded prefix of noise; they cannot permanently contaminate all later candidates. Musical evidence can overcome the visible-region prior, but an offscreen viewport request must satisfy the full reframe gate even when the marker could already acquire there. Initial offscreen acquisition cannot use advance merely because the acquired line is adjacent to the view: a visible prior line is not a previously confirmed musical path.

### 8.2 Occurrence identity

Index candidates using error-tolerant unions of pitch postings and ordered context. The rarest observed pitch may be the mistake; it cannot be a mandatory gate. Exact-mask and fingerprint matches may accelerate retrieval but cannot exclude partial chords, supersets, one-hand matches, or candidates with a plausible omission.

Retain ordinary local paths independently of global retrieval. Allocate candidate capacity to materially different destinations and to both continuity and new episodes. A rich set of hand substates at one location must not evict every other occurrence.

Repeated occurrences share musical information but not position. Their shared prefixes do not discriminate between them. Use absolute register, ordered pitch/interval movement, relative onset spacing, active-hand content, and subsequent distinguishing attacks to separate them. None of these is a guarantee of uniqueness in all scores.

When repeated regions are indistinguishable, an established continuous path remains the default. During acquisition, visibility can justify a provisional visible-occurrence commitment, with confidence reflecting that prior; it must not justify a disruptive offscreen move between indistinguishable alternatives. If plausible alternatives need different viewport actions, hold.

## 9. Support, confidence, and bounded search

Marginalize hand, tempo, error, and onset-assignment substates by exact score-moment destination. Do not publish an arithmetic mean of separated modes. A hand interpretation is a probabilistic alternative with a normalized prior, not an extra vote. Predictively equivalent states may combine probability; duplicated representations of the same explanation must not inflate it.

Keep three distinct internal quantities:

1. Support for the exact published beat, used by Update.confidence.
2. Support for a coherent local occurrence/mode, used by tracking quality.
3. Support for a particular safe visual action, used by presentation.

Thus a held beat can have modest confidence while an adjacent coherent local mode is well supported. Confidence during lost refers to the held published beat, not the most promising unpublished remote candidate. Confidence is a model estimate; it is not a claim of an empirically measured success rate without calibration.

A beam normalized only over survivors is insufficient. Bounded retrieval/pruning must retain conservative accounting for unseen competitive alternatives. One valid formulation uses represented destination mass S(d), total represented mass S, and a valid upper bound U on unrepresented mass on the same likelihood scale:

~~~text
conservative destination support = S(d) / (S + U)
~~~

This expression is a lower bound only if the represented and residual quantities have the stated meaning. A heuristic top-match score cannot be substituted and called a probability. If no useful residual bound exists, support for a disruptive action remains uncertified and the action is withheld. A named unresolved-equivalence class or a refined indexed query can provide the same conservative behavior without literally using this formula.

Residual uncertainty must evolve with new evidence. Later distinguishing observations may narrow an occurrence family or bound away earlier omitted candidates. A permanent lookup-truncated latch is prohibited; so is clearing it simply because time passed or the beam became small. Restart/acquisition normalization must not forget plausible repeated occurrences merely to restore confidence.

The correct candidate need not always be found instantly in a huge repetitive score. Bounded work and arbitrary-score immediate global recovery cannot both be guaranteed. Under unresolved search, continue local inference and gather distinguishing evidence while withholding unsupported movement.

## 10. Commitment and action thresholds

### 10.1 Evidence gates

Before changing beat, select a supported exact moment and classify the movement as local continuity/repair, a new visible episode, or a relocation requiring reframing. Before changing the viewport, separately check fresh predictive fit, ambiguity of the action, actual visibility, pending requests, and reading need.

Default starting parameters below are **engineering policy, not literature findings or calibrated reliability claims**. They make revision 1 executable as a design rather than leaving “high confidence” undefined. They require adjustment against representative traces before performance claims are made. Changing parameters must preserve every categorical invariant.

| Decision | Initial conservative support threshold | Additional requirements |
|---|---:|---|
| Initial acquisition anywhere / local forward beat commitment | 0.80 for exact destination | Fresh musical compatibility and coherent-mode support; no advancement on noise alone; an offscreen marker never implies a scroll |
| Established new episode, forward or backward, visible or offscreen; backward local correction | 0.95 for destination/new episode | At least two supported distinct onsets; better explanation than restrike/continuous repair; this commits music, not a viewport action |
| Ordinary adjacent-line advance | 0.98 for the safe action | tracking, fresh attack evidence, §13 visibility/need conditions; cannot be driven by held replay frontier |
| Discontinuous viewport jump | 0.995 for the safe action and destination occurrence | Committed current beat must also have at least 0.95 exact support; §11 reframe gate includes post-change or recovery corroboration and unseen-alternative accounting |

Default tracking-mode entry support is 0.90; initial acquisition requires this coherent-mode support as well as the exact-destination threshold. Loss of mode support below 0.70 or failure of recent musical fit causes uncertainty. Default loss threshold is local-mode support below 0.20, or unstructured-error explanation support above 0.80 over the recent evidence window. These use a default window of the last four inferred onset opportunities, marginalized over uncertain grouping; they are not counts of wrong MIDI notes. Early acquisition/recovery can use fewer available opportunities when individually informative. Returning to tracking requires fresh coherent fit, not merely renormalization after pruning.

Distinct thresholds serve different variables; an exact-beat confidence of 0.80 is not interchangeable with 0.98 support that every credible path justifies the same viewport action. Credible alternatives to an advance may differ slightly in beat if all support the same safe reveal and the committed anchor is compatible. Alternatives that need different reading regions block it.

### 10.2 Evidence units

A distinct performed onset is inferred, not a time bucket. A second hand completing a chord, another note in a roll, a restrike of the same onset, or a release is not automatically a second confirmation.

For a reframe, the model must strongly prefer at least two onset opportunities over a plausible one-cohort or duplicate explanation across the retained grouping alternatives. A remote candidate cannot certify itself simply by assigning the chord’s first two notes to two different score moments. Onset evidence must include ordered progression and destination-specific information, with correlated within-onset evidence capped.

Two onsets are a safety floor, never a sufficient rule. Repetitive or weak material may require many more or remain unresolved indefinitely. A single distinctive chord can update an acquired marker while the viewport waits for corroboration. Conversely, several repeated C notes can still be insufficient to authorize a jump.

### 10.3 Hysteresis

After a jump request, suppress competing ordinary movement while that request is pending. After its visibility is acknowledged, require fresh post-request evidence for another jump; do not reuse the same confirming suffix in reverse. Default: double the required posterior odds for an additional jump until two further coherent onsets support the current episode. A hard lockout is prohibited: sustained contradictory evidence must still allow correction.

Urgency near a visual edge increases the cost of holding but cannot waive onset corroboration, action ambiguity, or residual-search uncertainty. No deadline converts ambiguity into evidence.

## 11. Replay, skips, and reframing

### 11.1 Visible musical relocation

A coherent earlier destination inside the usable view may commit as replay. A coherent forward destination already visible may commit as visible recovery. A forward destination in a new episode uses the same musical episode gate as a backward destination; calling it visible recovery cannot bypass confirmation. A true continuous forward repair uses the local gate. Neither requires moving the view merely because score position changed.

Visibility means the currently needed passage fits in the usable range, not just that its onset touches a line boundary. During replay, determine reading need from the replay episode, not the old marker frontier. Repeated local loops remain stable. If the replay starts visible but its necessary continuation later becomes offscreen, reassess that new need using the ordinary presentation rules.

### 11.2 Discontinuous viewport gate

A jump is authorized only when all of the following hold:

1. A destination occurrence and current progress there are strongly supported by fresh coherent attacks, at the distinct occurrence/action and exact-current-beat thresholds in §10. Occurrence certainty cannot select an arbitrary current beat within a diffuse passage.
2. The intended passage is not sufficiently visible, or a necessary direct reframe is required to restore it.
3. At least two distinct performed onsets corroborate the relocation/recovery episode; a single anomalous cohort cannot move the frame.
4. For a new episode, the destination beats the best continuous repair and other credible destinations on comparable post-change evidence. Default minimum odds against the best continuous explanation are 100:1 for a new nonlocal episode, in addition to the support threshold. For actual continuity needing a direct reveal, use the continuity case in §11.3 instead of requiring it to defeat itself.
5. Shared motifs, alternative onset groupings, and unexamined candidates do not leave a competitive different action/destination.
6. Tracking has recovered to tracking, and the request is not forbidden by pending navigation handling.

After confirmation, target the line owning the current corroborated beat, not the episode’s now-obsolete starting beat. Set displayBeat to that committed beat and emit jump(toLine:). The host directly reveals the destination rather than animating through intervening systems.

### 11.3 Musical adjacency and visual distance

The viewport enum describes presentation, not the reason the pianist moved. An adjacent musical successor after several empty lines is still continuity, but revealing it may require a direct jump. It need not defeat continuity odds, because continuity is its musical explanation; it still needs high destination/action support and corroboration against a one-off anomaly. For this attack-free traversal only, corroboration may consist of recent coherent predecessor evidence plus the observed unique successor when no new episode is proposed.

A large omission that removes unread attacked material is more ambiguous than traversal of attack-free lines. It uses the discontinuous gate even if the search implementation happened to call it local, including at least two coherent performed onsets from the proposed recovery destination onward. Pre-omission history alone is not the second confirmation in this case. Do not issue a sequence of adjacent advances to evade that gate.

If the musical location commits before the viewport gate passes, beat may update while the frame stays unchanged. The marker follows §12, and future fresh attacks can authorize the necessary movement without requiring another beat change.

## 12. Marker policy

The user-confirmed marker policy retains a stable reading frontier:

- Initialize displayBeat at the first committed acquisition.
- On supported ordinary forward progress, advance it to the committed beat; no clock interpolation.
- Hold it during uncertainty, loss, and confirmed visible replay/backward correction until playing catches its previous frontier.
- A committed visible forward recovery may advance it immediately.
- On an authorized jump, set it to the current committed destination, even if that decreases it.
- A reset begins a new display epoch; monotonicity has no meaning across epochs.

Within an epoch, displayBeat cannot decrease unless that Update contains jump. This is a presentation policy, not a constraint on inference or beat. A held marker during replay is intentionally a reading frontier rather than an accurate sounding-position pointer; beat remains available for diagnostics. This choice is confirmed and is not left to implementer preference.

An offscreen acquired/committed beat may exist before a jump is authorized. The host should draw its marker only where that beat is actually displayed; it must not scroll to make a marker visible independently of viewport. Never use displayBeat to determine that a replay is about to reach a line boundary.

## 13. Viewport policy

### 13.1 Visibility means readable content

visibleRange is the continuous beat interval the user can actually read, excluding clipped, occluded, or merely buffered material. Treat its upper edge as exclusive for ordinary containment; the true score endpoint is allowed as a terminal boundary. A zero-width, nonfinite, wholly out-of-score, or absent range supplies no usable visibility. Clip harmless score overhang to the score domain. A small intersection with a line is not evidence that the whole line is readable.

With unknown visibility, continue musical acquisition/tracking and marker estimation, but emit no automatic movement. A later valid report makes presentation eligible on the next attack. A property write itself cannot return an Update and must not secretly emit one through another channel.

The host is responsible for describing a genuinely usable continuous region. If the layout displays disjoint pages or reordered excerpts, one enclosing range would falsely claim the gap is visible; that layout is not represented by this API.

### 13.2 Confirmed line entry

The user explicitly chose **confirmation of entry into the next line** as the ordinary scroll trigger. Reading studies do not override that product decision. There is no anticipatory time/beat reserve, no final-onset pre-scroll, and no exception for sparse attacks or long rests.

Entry means fresh performed attack evidence has committed musical progress to a moment owned by the target line, with sufficient support for the line-handoff action. A predicted next beat is not entry. A lagging hand’s note assigned to the previous moment is not entry. The display frontier left over from a visible replay is not entry. A sufficiently informative partial chord can confirm entry; the follower need not wait for all notes in its first chord.

The entry event is not restricted to the line’s first written moment. If the pianist omits that moment and clearly enters at a later one, the supported actual onset confirms entry. If evidence was ambiguous at the first attack, emit as soon as a later attack resolves it; do not add a fixed waiting interval after resolution.

Retain an unresolved handoff record containing the episode identity, preceding confirmed line, entered target line, and entry evidence. Committing beat into the target does not erase its eligibility while action confidence is still developing. Later evidence within the same line can authorize the delayed advance. Fulfilled visibility retires the handoff; replay, a new episode, or reset invalidates it. If progression outruns an unexecuted reveal, reclassify the target against the actual reading frame: skipping several still-unrevealed lines requires the direct-reframe gate rather than pretending each unexecuted adjacent advance occurred.

For a known range, a target line counts as fully readable only when the span of its owned measures is inside the usable range. Use owned measures rather than potentially overhanging Line.beatRange. Boundary equality is allowed for whole-region extent coverage, while an actual attack at the upper edge remains outside ordinary onset visibility. A sliver of its first measure or merely its starting beat is not a readable line. The host’s successful ordinary reveal is to make the entered target line readable.

If feedback after a request contains the committed attack and coupled active-hand anchor region but not the whole line, accept that observed result as partial fulfillment and reassess if later supported progress leaves it. This applies regardless of why the whole line was not shown; the follower does not infer screen capacity from the report. It is a conservative partial-line fallback, not permission to pre-scroll before entry. Actual range feedback controls acknowledgment; repeated attempts must not demand an unobserved whole-line fit.

### 13.3 Ordinary advance

Emit advance(toLine:) only when:

1. The current episode is tracking and recent received attacks support ordinary forward reading, including a resolved local repair; the triggering consume call supplies new confirmation under §4.3.
2. Musical progress has entered the adjacent target line under §13.2 and that line is not already readable in visibleRange.
3. Credible interpretations agree that the performance has made this handoff; it is not an isolated extra note that might belong to the old line’s chord or a momentary early/late-hand ambiguity.
4. The target and current coupled-hand reading anchor are compatible with the reveal; missing tones, already struck held notes, and inactive lanes do not require waiting for chord completion or physical release.
5. The safe-action support threshold is met and no conflicting request is pending.

An advance means reveal the **currently entered** line through an ordinary forward viewport transition. It never targets a future unentered line. Preserve a familiar visual landmark where the layout allows, but an overlap requirement must not become an earlier trigger or a requirement to retain an already completed line indefinitely. The view chooses its animation and alignment; this model supplies the line and action, not animation duration.

Once all conditions pass, emit on that consume call. Do not wait for another onset, an arbitrary debounce period, all keys to release, or the last note of the entry chord. One partial onset can confirm an ordinary handoff from an already coherent path; this does not weaken the multi-onset gate for a new offscreen episode.

If the line was already fully visible on entry, return unchanged. Continue evaluating current visibility on later attacks. If it later becomes clipped without userReset, or supported progress moves beyond an acknowledged partial-line region, a same-line forward reveal may use advance(toLine:) for that already entered line. It is not a new musical handoff or a license to reveal the following line. Reject redundant requests when the achieved region still contains current progress and visibility has not changed.

There are no attacks generated at notated line boundaries. The final onset of the previous line, its sustain ending, and silence before the next line never trigger an advance. A next relevant attack across multiple empty systems still waits for observed entry and uses §11.3 if direct reframing is necessary.

### 13.4 Screen-capacity limitation

The reference and current range cannot prove the geometry of a hypothetical reveal. The host should make the entered line readable and retain nearby context when possible; no new geometry input is required. The partial-line fallback in §13.2 prevents a request loop on a view that cannot show a whole system.

On a one-line display, confirming entry can require the pianist to play the first attack before that notation is revealed. This is the accepted consequence of the user’s entry-trigger choice, not a reason to silently restore anticipation. The model guarantees no intentional early trigger and no intentional post-confirmation delay. Evidence ambiguity and view execution latency can still delay visible movement; neither is solved by claiming access to the pianist’s intention.

### 13.5 Requests, feedback, and manual control

Maintain at most one pending viewport intent: action class, target line, required region, and the evidence/navigation epoch that justified it. Emission does not change visibleRange or reinforce musical confidence.

Update.viewportRevision makes this intent revocable without a new input endpoint. Increment the revision when issuing a request, or when canceling an outstanding intent. Subsequent unchanged Updates with the same revision do not reissue or cancel it. An unchanged Update with a newer revision cancels all older queued/deferred requests. The host applies a deferred request only if its revision is still current; a new advance/jump revision replaces older authority. Revision resets with a hard/new-reference epoch, and the caller explicitly clears old requests whenever it initiates a reset, so revisions from different epochs are never compared.

Cancel an outstanding intent when tracking becomes uncertain/lost, a committed replay/correction or new episode makes its target inappropriate, or actual visibility/progress makes its action obsolete. Cancellation is published before any later application; it does not command a return to an old viewport. Already executed motion cannot be undone retroactively, so the host reports the actual resulting view and uses current authority for subsequent movement. Do not leave a delayed advance queued while the pianist is visibly replaying the previous line. Canceling a request for uncertainty may retain the unresolved musical handoff for reconsideration if the same episode later recovers; canceling for a new episode removes that handoff.

The host must report the actual resulting range after handling a recommendation, including when the recommendation could not be applied. A report acknowledges full fulfillment when the target line is readable, or partial fulfillment when the current attack/active-hand anchor region is readable under §13.2. Partial fulfillment suppresses retries for the same musical progress; only later unsupported-by-visibility progress or a changed range can justify another reveal. A report that does not contain even the current anchor is not success. The host serializes reports; this API cannot identify delayed reports from an older request.

Suppress duplicate or competing ordinary recommendations while a request is unresolved. After a feedback report that leaves it unfulfilled, retry only on a later fresh attack with materially changed musical progress/need or a changed usable range. Do not resend on every chord tone. If the host never reports visibility after a request, retain pending status and withhold further ordinary requests; this is an integration failure, not grounds for guessing success.

A newly confirmed incompatible jump can supersede a pending ordinary advance using fresh evidence and the full jump gate. The host must consume Updates in order and discard an older deferred intent whenever its revision is invalidated or after navigation/reset. A userReset immediately cancels all previous authority without needing to emit an Update.

The user’s desired manual-scroll behavior is to ignore MIDI during scrolling, rather than defer scroll recommendations computed from it. Ignored input must not update alignment, physical evidence, performer calibration, episode confirmation, or output, and must not be queued for later replay. The user explicitly deferred deciding how the scrolling interval is communicated. This revision therefore does not add a scrolling flag, infer completion from elapsed time, or mandate a new forwarding contract. The five-operation follower processes events supplied to consume; identifying/excluding the scrolling interval remains a recorded integration issue outside the current design scope. userReset still revokes old authority immediately, and the first subsequent attack must not be described as proof that a drag ended.

## 14. Boundedness and determinism

Compile immutable occurrence indexes, successor relations, ownership, and short pattern descriptors from the full reference. Score-sized immutable storage is expected. Keep capped active hypotheses, suffix history, onset substates, and candidate evaluations per event. Indexed access may have logarithmic score-size cost; no unconditional linear scan is allowed on consume.

Use separate bounded capacity for continuity and new episodes, and preserve destination diversity before detailed hand/timing variations. Local polyphonic modeling may be richer than broad candidate discovery, but every candidate reaches the same commitment and presentation gates. A second trusted-anchor extrapolator cannot bypass them.

If a computational limit prevents evaluating a competitive destination, uncertainty must increase or remain unresolved. It cannot disappear through pruning. Repeated input bursts must not grow history, active hypotheses, pending requests, or physical state without bound. Exact budget sizes are engineering resource parameters, not musical truth; evaluation must include adversarial scores that exceed them.

Given the same canonical reference, ordered events, timestamps, visibility reports, lifecycle calls, and parameter set, public output must be deterministic. Tie ordering affects representation only; a tie between different required viewport actions resolves to unchanged. Future observations and callback scheduling must not leak into a replayed trace’s earlier decisions.

## 15. Required observable scenarios

These are acceptance behaviors, not an implementation sequence. Trace fixtures must annotate where the observations actually distinguish the intended interpretation; an ambiguous example must not demand clairvoyance.

| Scenario | Required observable outcome |
|---|---|
| Arbitrary start with a distinctive partial chord | Can acquire before all chord tones arrive; offscreen movement still waits for its stronger gate |
| Initial wrong note, then informative correct passage | Early noise does not permanently poison acquisition |
| Common note or identical repeated prefix at many positions | Holds or maintains a justified prior-based visible estimate; never invents uniqueness |
| Expected {60,64,67,71}, performed 60,64,67,70,71 as one credible cohort | Extra 70 is absorbed; late 71 remains a chord member; no false multi-onset confirmation |
| Same chord played slowly as a roll | Timing widens alternatives; no fixed deadline forces several score transitions |
| Actual fast succession of notes | Strong pitch/order context can advance despite short time intervals; no universal chord window merges them |
| One missing tone, entire missing onset, several skipped onsets | Local omission hypotheses remain available; a strong actual destination can commit without waiting for one more exact chord |
| Consecutive wrong notes followed by clear local continuation | Confidence falls; onset does not absorb forever; local recovery is possible without global relocation |
| Repeated note with a release / without a received release | Both remain attacks; score context distinguishes restrike from scored repetition |
| Left leads, right catches up; reverse ordering | No double advancement for one scored onset; no loss merely from lane order |
| One hand is silent or a second hand joins | No mode selection and no requirement to play every reference lane; participation adapts |
| One pitch belongs to both hands | No duplicated likelihood or false certainty that both hands played |
| Pedaled/legato overlap across chords | Key/sound overlap does not merge successive score attacks or wait for pedal-up |
| Strong rubato, abrupt slowdown, invalid timestamps | Following remains pitch/sequence capable; tempo uncertainty widens instead of forcing a remote destination |
| Long pause plus expected successor | Local resumption; pause interval does not become a new tempo or choose a jump |
| Silence after final attack or during long rest | No later spontaneous marker/viewport update |
| One remote-looking anomalous chord | No viewport movement caused by that anomaly |
| Coherent visible backward replay | beat follows confirmed replay; default displayBeat and viewport hold until catch-up |
| Coherent offscreen restart | Current destination is revealed after corroboration, dominance, and ambiguity checks; not necessarily the first restart beat |
| Good long history but sustained recent match elsewhere | Old history cannot prevent a supported new episode from winning |
| Scattered remote-like errors separated by local recovery | No accumulated remote confirmation across the recovered passages |
| Two identical occurrences remain indistinguishable | No disruptive switch based on beam/order/timeout; later unique continuation can resolve them |
| Rare extra pitch during global search | Correct candidates remain eligible through other evidence |
| Candidate limit exceeded, then a distinctive continuation | Hold while alternatives are unresolved; recover after the ambiguity is actually narrowed |
| Incorrect jump followed by clear corrective passage | Hysteresis delays oscillation but does not permanently disarm correction |
| Musical successor across empty engraved lines | Musical continuity remains intact; direct presentation, if necessary, uses its own strong gate |
| Several lines already readable | viewport scrolls line by line, the extra lines can serve as margin |
| Only first beat of target line visible | Not treated as sufficient upcoming readable context |
| Final onset before an unread line, however short or distinctive | No advance; the target line has not yet been entered |
| Long held onset/rest before an unread line, no intervening events | No early reveal and no timer; wait for confirmed played entry |
| Strong partial first onset in next line, after coherent continuity | Advance on the confirming consume call if the line is unreadable; do not wait for chord completion |
| First written onset of next line omitted | Later supported actual entry can advance; no demand to replay the missing first onset |
| Leading hand seems at new line but credible current-line assignment remains | Hold until handoff is supported; inactive-hand omissions and already struck sustains do not impose a release gate |
| Automatic request delayed or refused | No assumed viewport change, self-confirmation, or command storm |
| Advance queued, then uncertainty or visible replay occurs | New viewportRevision cancels stale queued authority; unchanged does not allow the old advance to execute later |
| Entry beat commits before the advance threshold passes | Handoff remains eligible; later confirming evidence in that same line emits the needed advance |
| Feedback shows current anchor but only part of the requested line | Accept partial fulfillment without inferring screen capacity; do not retry until visibility or relevant progress changes |
| userReset during a partial chord | Old assignment/action authority and physical certainty are canceled; fresh music and current visibility govern |
| MIDI during manual scrolling | Desired behavior is complete exclusion without later replay; scrolling-interval signaling is explicitly deferred, not inferred by the follower |
| Hard reset with same score | Behavior is fresh-start equivalent, including no retained visibility, calibration, hands, pedals, or pending movement |
| Reference replacement with new layout | No old line identifier, onset state, or viewport intent survives |
| Unknown/invalid visibility | Musical following can continue; automatic viewport remains unchanged |
| Same music, different line wrapping | Established musical inference is unchanged; only presentation decisions change |

Evaluation must cover real timestamped piano practice as well as controlled perturbations. Split calibration and evaluation by performer and score where possible; do not tune and claim success on the same traces. Include novices/slow practice, experienced expressive playing, dense/monophonic passages, repeated structures, different screen capacities, and missing timing/release information.

Report separately: false advances, false jumps, unnecessary movement, missed/late required reveals, time stuck, onset commitment/recovery latency, repeat ambiguity duration, confidence calibration, and pianist loss-of-place/disruption reports. Also measure event-processing latency and maximum mutable state in release builds as score size and repetition grow. No single alignment-accuracy number establishes a good scrolling product. No claimed zero false-scroll rate follows from this document’s probability thresholds.

## 16. Evidence and its limits

The architecture is a synthesis of score-following research, empirical piano-performance findings, music-reading studies, and the user’s stated preference for a stable view. The particular API, marker policy, reset behavior, support thresholds, and confirmed-entry scroll trigger are product decisions. They are not prescribed by neuroscience or by one published algorithm.

1. **Nakamura, Ono, Sagayama & Watanabe — A Stochastic Temporal Model of Polyphonic MIDI Performance with Ornaments.** Models errors and timing at different musical levels; within-chord and between-event intervals can overlap. This supports retaining candidate-conditioned onset assignments rather than a fixed chord window. It does not establish universal milliseconds or guarantees for all practice behavior. [Primary paper](https://arxiv.org/abs/1404.2314).

2. **Nakamura, Ono, Saito & Sagayama — Merged-Output Hidden Markov Model for Score Following of MIDI Performance with Ornaments, Desynchronized Voices, Repeats and Skips, ICMC/SMC 2014.** Supports coupled polyphonic interpretations and cross-voice reordering. Its experiments also illustrate that richer local modeling can trade improved alignment for slower repeat recovery; local detail and global recovery need separate resource attention. The venue is ICMC/SMC, correcting an error in the earlier review. [Primary paper](https://eita-nakamura.github.io/articles/Nakamura_etal_MergedOutputHiddenMarkovModelForScoreFollowing_2014.pdf).

3. **Nakamura et al. — Outer-Product Hidden Markov Model and Polyphonic MIDI Score Following.** Supports probabilistic errors, repeats/skips, and efficient structured inference. Its analysis relates recovery to destination ambiguity and information in observations; a universal count of matching notes is not a uniqueness guarantee. Its efficient full-state formulation does not prove constant event work for this bounded approximation. [Primary paper](https://arxiv.org/abs/1404.2313).

4. **Nakamura et al. — Autoregressive Hidden Semi-Markov Model of Symbolic Music Performance for Score Following, ISMIR 2015.** Distinguishes timing relationships within and between score events. This supports separating onset microtiming from progression/tempo; its distribution parameters are modeling choices, not product constants. [Primary paper](https://eita-nakamura.github.io/articles/Nakamura_etal_ARHSMMForScoreFollowing_ISMIR2015.pdf).

5. **Jiang & Raphael — Score Following with Hidden Tempo Using a Switching State-Space Model, ISMIR 2020.** Shows the usefulness of a changing latent tempo in piano audio alignment. The design borrows that modeling principle; its reported audio results are not MIDI follower accuracy predictions. [Primary paper](https://archives.ismir.net/ismir2020/paper/000159.pdf).

6. **Adams & MacKay — Bayesian Online Changepoint Detection.** Provides a framework for uncertainty over when a new segment began. Episode-owned evidence and change-point competition here are an application of that principle, not a claim that its original observation assumptions directly model polyphonic piano. [Primary paper](https://arxiv.org/abs/0710.3742).

7. **Nakamura, Yoshii & Katayose — Performance Error Detection and Post-Processing for Fast and Accurate Symbolic Music Alignment, ISMIR 2017.** Demonstrates that apparent performance errors may be alignment errors worth reconsidering. This work is offline; bounded reconsideration of already received notes here does not inherit its access to future observations or accuracy results. [Primary paper](https://eita-nakamura.github.io/articles/EN_etal_ErrorDetectionAndRealignment_ISMIR2017.pdf).

8. **Goebl — Melody Lead in Piano Performance: Expressive Device or Artifact?, 2001.** Observed differentiated onset timing in skilled pianists and examined instrument-action/dynamic effects. Supports treating simultaneity and hand-leading assumptions cautiously; it does not make MIDI timestamp equivalent to finger contact or justify a universal chord window. [Primary paper](https://iwk.mdw.ac.at/goebl/papers/Goebl_JASA2001_melodyLead.pdf).

9. **Rosemann, Altenmüller & Fahle — The Art of Sight-Reading, 2016.** A small pianist study found eye–hand span depended on tempo/complexity. This supports variable reading needs, not a universal beat reserve or an inferred individual gaze location. [Primary study](https://journals.sagepub.com/doi/abs/10.1177/0305735615585398).

10. **Imai-Matsumura & Mutou — The Influence of Executive Functions on Eye–Hand Span and Piano Performance during Sight-Reading, 2023.** Reports associations among score difficulty, eye–hand span, working memory, and performance in experienced players. It does not justify diagnosing cognitive load from MIDI or making causal claims about a particular scroll policy. [Primary study](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0285043).

11. **Cara — The Effect of Practice and Musical Structure on Pianists’ Eye–Hand Span and Visual Monitoring, 2023.** Supports the role of musical structure and monitoring in anticipation. Correct DOI: 10.16910/jemr.16.2.5. It supplies no fixed ideal scroll delay. [Primary study](https://pmc.ncbi.nlm.nih.gov/articles/PMC10696908/).

12. **Tabone, Bonnici & Cristina — Automated Page Turner for Musicians, 2020.** Uses overlapping half-page updates and gaze-informed transition handling, recognizing that readers may inspect both systems. This motivates preserving reading context and explicit host behavior. Its gaze/tempo inputs are absent here, so its trigger rule and success rate cannot be transplanted into this MIDI-only design. [Primary study](https://www.frontiersin.org/journals/artificial-intelligence/articles/10.3389/frai.2020.00057/full).

These sources support a flexible musical interpretation and a cautious presentation policy. They do not prove that the particular revision-1 thresholds or scroll trigger are optimal. Findings about visual anticipation do not authorize scrolling before the user’s chosen confirmed-entry trigger. User studies and representative performance traces are necessary to evaluate the resulting experience.

## 17. Confirmed decisions, deferred scope, and authority

This revision resolves the earlier documents’ main contradictions:

- Public reset exists and is a true hard reset, as requested.
- Jump confirmation uses a two-onset minimum plus destination-specific evidence, not a sufficient fixed count of two or three.
- Musical continuity can require a discontinuous visual reveal across empty lines; the viewport enum describes that visual action.
- Ordinary scrolling occurs exactly on sufficient confirmation of entry into the next unreadable line. The user rejected anticipatory scrolling; final-onset and tempo-reserve triggers are excluded.
- Confidence names an exact destination and includes search uncertainty rather than renormalizing survivors into false certainty.
- Viewport requests have an output revision so later uncertainty/replay can revoke deferred movement; this adds no new input endpoint.
- Manual navigation discards positional authority and stale physical state but retains broad performer calibration.

The user confirmed the stable marker frontier during visible replay. It is a requirement, not an optional implementation choice.

The user also specified ignoring MIDI during manual scrolling, then explicitly deferred the mechanism for identifying that interval. No scrolling-state input or caller-gating mechanism is chosen in this revision. This is the sole deferred integration question; it must not be described as solved by userReset alone. Do not block the musical-model implementation on it or invent an extra endpoint.

No new reference field or external input has been approved or made necessary. Numerical policies remain initial engineering defaults until evaluated; they are not experimentally validated guarantees. An implementer may choose data structures and probability-distribution parameters consistent with the defined evidence model, but may not change the confirmed trigger, marker behavior, reset semantics, or ambiguity safeguards without updating this sole specification deliberately.
