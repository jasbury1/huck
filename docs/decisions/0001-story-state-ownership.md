# Story State Ownership

**Status:** Adopted
**Date:** 2026-08-16
**Applies to:** `StoryModel`, `InteractionStore`, `StoryCache`, and every view that
displays a story (`StoryCellView`, `StoryTextView`, and future profile/search rows).

## The rule

> **`StoryModel` is an immutable, write-once snapshot of a story's server-fetched
> content. All mutable, user-derived state lives in an id-keyed store
> (`InteractionStore`), never on `StoryModel`.**

Concretely:

- `StoryModel`'s fetched fields (`title`, `by`, `score`, `commentCount`, `url`,
  `text`, `timestamp`, `storyType`, `thumbnailStatus`) are populated exactly once by
  `fetchData()` and are `private(set)` so nothing outside the model can change them.
- Anything the user changes, or that otherwise diverges from that first snapshot —
  upvote state, the optimistic effect of a vote on the score, saves, hides — is owned
  by `InteractionStore`, keyed by story **id**.
- Views render by combining the two: e.g. the displayed score is
  `storyData.score + interactionStore.scoreDelta(for: id)`.

## Why (the bug that motivated it)

The same story is represented by **more than one `StoryModel` instance**:

- `StoriesFeedData` owns one per feed row (`models[id]`).
- `StoryTextView.init` creates its own `StoryModel(id:)`.
- A profile/search view could create a third.

`StoryModel` was a mutable `@Observable` class, and the upvote code mutated
`story.score` on whichever instance the tap came from. Because the instances are
distinct objects, the ±1 landed on different `score` fields while the shared
`isUpvoted` flag flipped globally. Bouncing between the feed and the comments view
and toggling the vote let the feed's counter march downward without bound, while the
comments view showed a different number — the two were never reconciled.

The defect was structural: **we mutated a per-view copy of shared identity.** Score
was simply the first field we tried to mutate; any mutable field would have exhibited
the same class of bug.

## The two coherent designs we considered

**A. Unify `StoryModel` identity per id.** A shared model registry (keyed by id, with
LRU eviction like `StoryCache`) that every view vends from, so there is exactly one
instance per story app-wide. Mutations reflect everywhere; fetch/thumbnail work
dedups. Cost: a new cache layer with its own memory management, touching
`StoriesFeedData`, `StoryTextView`, and `UserView`.

**B. `StoryModel` is an immutable snapshot; mutable state lives in id-keyed stores.**
Duplicate `StoryModel` instances become harmless because they are read-only
projections of the same cached data. Anything that changes over time becomes a store
overlay keyed by id.

## Decision: adopt B

The app already layers responsibilities this way — `StoryCache` owns fetched data,
`InteractionStore` owns user state — so B is the consistent, lighter-weight choice.
We were also nearly there already: `fetchData()` is write-once (guarded by
`isLoaded`), so the only thing violating the invariant was the vote's score
mutation.

Under B:

- The optimistic vote effect became `InteractionStore.scoreDeltas[id]` (a per-story
  overlay, not persisted — on relaunch the refetched score is truth), and views show
  `base + delta`. Because the base comes from the shared `StoryCache` it is identical
  across instances, so every view for a story shows one value.
- `StoryModel`'s fetched fields were made `private(set)` to make the write-once rule
  **compiler-enforced** rather than a convention someone can accidentally break.

We explicitly **deferred option A**. `StoryCache` and `ThumbnailCache` already
coalesce the expensive network/decode work, so sharing the model object saves only a
little redundant populating — the real argument for A is consistency, not
performance, and B gives us that consistency without adding a cache layer.

## When to revisit (adopt A, or add another overlay store)

Reach for a shared `StoryModel` registry (option A), or a new id-keyed overlay store,
when we introduce **content that legitimately changes over time**, such as:

- Live-refreshing scores or comment counts (a story's score climbing while viewed).
- Any server-driven update that should appear across all views without a full refetch.

At that point, either unify the instance (A) or model the changing field as an
id-keyed overlay (the same pattern as `scoreDelta`). **Do not** re-introduce a
settable field on `StoryModel`; that is exactly the pattern this rule prohibits.

## Checklist for adding new per-story state

1. Is it fetched-once server content? → It belongs on `StoryModel` as `private(set)`,
   set only in `fetchData()`.
2. Is it user-derived or does it diverge from the fetched snapshot (votes, saves,
   hides, optimistic overlays)? → It belongs in `InteractionStore`, keyed by id.
3. Never add a publicly settable property to `StoryModel`.
