# SafariView — the in-app browser, layer by layer

This document walks through how Huck presents an in-app Safari browser when a
user taps a link story, and which SwiftUI behavior each step relies on. The code
lives in `HuckApp/Views/StoryViews/SafariView.swift`, with the tap sites in
`StoryCellView.swift` and `StoryTextView.swift`.

We follow one real interaction: a user taps a link story and later dismisses the
browser.

## The cast of characters

There are five pieces, in two files:

| Piece | Where | Role |
|---|---|---|
| `.inAppBrowser()` / `InAppBrowserModifier` | `SafariView.swift` | Owns the presentation state and the cover |
| `OpenInAppBrowserAction` | `SafariView.swift` | The callable "please open this" token |
| `\.openInAppBrowser` env entry | `SafariView.swift` | The wire that carries the action down the tree |
| `SafariView` (`UIViewControllerRepresentable`) | `SafariView.swift` | Bridges UIKit's `SFSafariViewController` into SwiftUI |
| `Coordinator` | `SafariView.swift` | Listens for UIKit's "user is done" callback |

---

## Layer 0 — Setup, before anything is tapped

When `FeedView`'s body builds, `.inAppBrowser()` wraps the `NavigationStack` in
`InAppBrowserModifier`. Two things get installed at that point:

**1. A piece of state is born:**

```swift
@State private var link: BrowserLink?
```

`@State` means SwiftUI allocates persistent storage for this modifier and
*watches* it. Starting value is `nil` → nothing presented. The rule to remember:
**when `link` changes, SwiftUI re-runs the modifier's `body`.** That single fact
drives everything below.

**2. The action is injected into the environment:**

```swift
.environment(\.openInAppBrowser,
             OpenInAppBrowserAction { link = BrowserLink(url: $0) })
```

This replaces the harmless default action (a no-op `{ _ in }`) for *this subtree
only*. The real action captures `link` — its whole job is: "given a URL, set my
state." Note the closure captures the modifier's `@State`, so calling it later
writes back into this exact storage.

So after setup: every descendant of the `NavigationStack` can now read a live
`openInAppBrowser` action that, when called, flips `link` from `nil` to a value.

**SwiftUI behavior used:** `@State` (framework-owned reactive storage) and the
**environment** (implicit top-down value propagation, `.environment(_:_:)`
writing / `@Environment` reading).

---

## Layer 1 — The tap

Deep inside the tree, `StoryCellView` has:

```swift
@Environment(\.openInAppBrowser) private var openInAppBrowser
```

`@Environment` walks *up* the tree at body-evaluation time and grabs whatever
value was most recently installed for that key — which is the real action from
Layer 0, not the no-op default.

User taps a link story → `openStory()` runs → `openInAppBrowser(url)`.

That call syntax works because `OpenInAppBrowserAction` defines
`callAsFunction(_:)`. `openInAppBrowser(url)` is sugar for
`openInAppBrowser.callAsFunction(url)`, which runs `handler(url)`. And `handler`
*is* the closure from Layer 0, so this executes:

```swift
link = BrowserLink(url: url)
```

**SwiftUI behavior used:** `@Environment` (upward lookup of an injected value) +
Swift's `callAsFunction` (why the value is callable like a function).

---

## Layer 2 — State change triggers presentation

`link` just went `nil → BrowserLink(...)`. Because it's `@State`, SwiftUI
**invalidates the modifier and re-runs its `body`**. On this pass it
re-evaluates:

```swift
.fullScreenCover(item: $link) { link in ... }
```

`fullScreenCover(item:)` is the item-driven modal. Its contract: while the bound
optional is `nil`, nothing shows; the moment it becomes non-`nil`, SwiftUI
presents the modal and hands the *unwrapped* value into the builder. That's why
it needs `BrowserLink: Identifiable` — SwiftUI uses `id` to know *which* item is
showing and whether it changed.

> Why `BrowserLink` exists at all: `fullScreenCover(item:)` requires
> `Identifiable`, and `URL` isn't. Rather than conform `URL: Identifiable`
> app-wide (which would leak into everyone else's code), we wrap it in a tiny
> private struct whose `id` is the absolute string.

The builder runs:

```swift
SafariView(url: link.url) { self.link = nil }
    .ignoresSafeArea()
```

Two things handed to `SafariView`: the **URL** to load, and an **`onFinish`
closure** that sets `link = nil`. Hold onto that closure — it's the dismissal
path in Layer 4. `.ignoresSafeArea()` lets Safari's own chrome extend
edge-to-edge instead of being inset.

**SwiftUI behavior used:** state-driven re-evaluation of `body`, and
`fullScreenCover(item:)` (declarative, data-driven modal presentation keyed on
`Identifiable`).

---

## Layer 3 — Bridging into UIKit

`SafariView` is a `UIViewControllerRepresentable` — the official adapter for
putting a `UIViewController` inside SwiftUI. SwiftUI drives its lifecycle by
calling three methods in order:

**1. `makeCoordinator()`** — called *first*, once. It builds a `Coordinator`,
passing the `onFinish` closure into it. The coordinator is SwiftUI's official
place to hold the objects that must survive across updates and to serve as a
**delegate/target** for UIKit callbacks — UIKit talks back through delegates,
and SwiftUI structs are transient value types that can't be delegates, so the
reference-type `Coordinator` (an `NSObject`) fills that role.

**2. `makeUIViewController(context:)`** — called once to create the actual UIKit
object:

```swift
let controller = SFSafariViewController(url: url)
controller.delegate = context.coordinator
return controller
```

It instantiates the real Safari controller with the URL, and wires its
`delegate` to the coordinator SwiftUI just made (reachable via
`context.coordinator`). SwiftUI then hosts this controller inside the full-screen
cover. At this instant the page begins loading and the standard chrome appears.

**3. `updateUIViewController(_:context:)`** — empty, and correctly so. SwiftUI
calls it whenever surrounding state changes, to let you push new data into the
controller. But `SFSafariViewController` is immutable after creation — you can't
hand it a new URL — so there's nothing to sync. Empty is the right
implementation, not an oversight.

**SwiftUI behavior used:** `UIViewControllerRepresentable` lifecycle
(`makeCoordinator` → `makeUIViewController` → `updateUIViewController`) and the
**Coordinator pattern** for receiving UIKit delegate callbacks.

---

## Layer 4 — Dismissal, and closing the loop

User taps **Done** (or swipes the browser away). `SFSafariViewController` reports
this to its delegate — our coordinator — by calling `safariViewControllerDidFinish`:

```swift
func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
    onFinish()
}
```

`onFinish` is the closure from Layer 2: `{ self.link = nil }`. So this sets
`link` back to `nil`.

And now the cycle closes exactly the way it opened: `link` changed → `@State`
invalidates the modifier → `body` re-runs → `fullScreenCover(item:)` sees a `nil`
item → SwiftUI **animates the cover away**. State is the single source of truth
in both directions — setting it presents, clearing it dismisses.

> Why route dismissal through our own state instead of letting Safari close
> itself: inside a SwiftUI `fullScreenCover`, the thing that "owns" whether the
> modal exists is `link`. If Safari tried to dismiss its own hosting controller,
> SwiftUI's state would still say "presented" and they'd disagree. By funneling
> Done → `onFinish` → `link = nil`, SwiftUI's state stays the authority and the
> cover tears down cleanly.

**SwiftUI behavior used:** delegate callback flowing back into `@State`, and the
same state-driven presentation logic running in reverse to dismiss.

---

## The whole loop in one breath

```
setup:   .inAppBrowser() installs @State link=nil + injects openInAppBrowser action
tap:     StoryCellView reads action via @Environment → calls openInAppBrowser(url)
                                        (callAsFunction → handler → link = BrowserLink(url))
present: @State change → body re-runs → fullScreenCover sees non-nil → builds SafariView
bridge:  makeCoordinator → makeUIViewController creates SFSafariViewController, delegate = coordinator
dismiss: Done → delegate's safariViewControllerDidFinish → onFinish() → link = nil
         → body re-runs → fullScreenCover sees nil → cover animates away
```

The throughline: **`link` is the single source of truth.** The environment
action's only power is to *set* it; the cover's only job is to *reflect* it; the
coordinator's only job is to *clear* it. Everything else is SwiftUI reacting to
that one optional changing.
