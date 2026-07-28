# WeChat Moments — Non-Functional Requirements

> **Purpose:** define *how well* the application must behave — concurrency, resilience to bad data, layout adaptivity, and testability — and *how compliance is evaluated*. This document states requirements; it deliberately avoids choosing APIs, libraries, or code patterns where the choice is still open. Those are recorded as **Future Architecture Decisions (FAD)** and resolved in [`architecture-specification.md`](./architecture-specification.md).
>
> **Companion documents:** [`functional-specification.md`](./functional-specification.md) (what the app does) and [`architecture-specification.md`](./architecture-specification.md) (how it is structured).
>
> **Normative language:** **MUST** = mandatory · **SHOULD** = strongly recommended · **MAY** = optional. Requirement IDs are stable references (`NFR-<AREA>-NNN`).
>
> **Scope guard:** this document covers four areas only — Performance & Concurrency, Data Resilience, Layout Adaptivity, and Testability. Localization, theming, accessibility, security, offline support, and analytics are **out of scope** for this exercise; see [`README.md §5`](./README.md) for the reasoning.
>
> **⛔** marks a requirement the current code does not satisfy. **⚠️** marks a contentious or blocking open item.

---

## 1. Performance and Concurrency (`NFR-PERF`)

### 1.1 Objective

The feed **MUST** scroll smoothly while dozens of remote images load. The brief calls this out directly: *"Utilise GCD for multi-thread operation."* Today the app does the opposite of this — every image load blocks whichever thread asks for it.

### 1.2 Scope

- **In scope:** thread affinity of network I/O and JSON decoding, the image-loading pipeline, image caching, cancellation, and the thread on which UI state is published.
- **Out of scope (for now):** the concurrency *mechanism* for images (GCD vs. Combine vs. `async/await`), the cache eviction policy, and image downsampling strategy — all **FAD** (§1.9).

### 1.3 User-visible behaviour

- Scrolling is smooth from the first frame; no cell blocks the list waiting for its images.
- A cell shows a placeholder immediately and swaps in the real image when it arrives.
- Scrolling past a cell and back does not re-download its images.
- The initial loading indicator reflects real in-flight work (`FR-FEED-003`).

### 1.4 Requirements

| ID | Level | Requirement |
|----|-------|-------------|
| `NFR-PERF-001` | MUST | Network requests and JSON decoding **MUST NOT** execute on the main thread. |
| `NFR-PERF-002` | MUST | Image loading **MUST** be asynchronous. A synchronous, blocking image API **MUST NOT** exist in the codebase. *`ImageHelper` was deleted in commit 03 and replaced by `Services/ImageLoader.swift`, whose only entry point takes a completion handler and returns immediately. No `Data(contentsOf:)` call for a remote URL remains.* |
| `NFR-PERF-003` | MUST | Loaded images **MUST** be cached in memory and served from cache on subsequent requests for the same URL. *`ImageLoader` consults an `NSCache` before the network, keyed by URL **and** pixel size (§1.11). Pinned offline by `ImageLoaderTests`.* |
| `NFR-PERF-004` | MUST | All published UI state changes **MUST** be delivered on the main thread. *(Satisfied for network results via `.receive(on: RunLoop.main)`; for images, `ImageLoader` delivers every completion through `DispatchQueue.main.async`. The one exception is deliberate: a cache hit answers synchronously on the calling — main — thread, because hopping a runloop turn for an image already in memory would flash the placeholder on every scroll-back.)* |
| `NFR-PERF-005` | MUST | The image API **MUST** deliver a result on **every** path — success, failure, and invalid URL. *`ImageLoader.loadImage(from:targetSize:displayScale:completion:)` invokes its completion with `nil` on absent URL, transport failure, non-2xx status and undecodable bytes. This is the exact defect `ImageHelper` carried — a callback inside the `if let`. Four of the `ImageLoaderTests` exist for this one requirement.* |
| `NFR-PERF-006` | SHOULD | An in-flight image request for a cell that has scrolled off screen **SHOULD** be cancellable, and duplicate concurrent requests for the same URL **SHOULD** be coalesced. *Both met: `ImageLoader` refcounts subscribers per URL, so concurrent requests share one `URLSessionDataTask` and it is cancelled only when the last subscriber leaves. `RemoteImage` holds the token in `@State` and calls `cancel(_:)` from `.onDisappear`. Three tests cover it, including one asserting that cancelling one sharer still delivers to the other.* |
| `NFR-PERF-007` | SHOULD | Images **SHOULD** be downsampled to their display size before being held in memory. *Met via ImageIO thumbnails on the decode queue (§1.12). The display scale travels with the request rather than living on the loader, because it is a property of the display, not of the cache.* |
| `NFR-PERF-008` | MUST | Pagination (`FR-PAGE-002`) reads from the in-memory list and **MUST** be a synchronous, allocation-cheap operation — appending a page **MUST NOT** hit the network. |

### 1.5 Engineering constraints

- `Data(contentsOf:)` **MUST NOT** be used for remote URLs anywhere in the codebase. It is synchronous, uncancellable, and has no timeout control.
- Any API that returns an image must either be genuinely asynchronous (callback, publisher, or `async`) or read from a cache that is already populated. A function that starts an async load and immediately returns a local variable is a defect — `TweetView.avatar(_from:)` and `TweetView.fetchImage(_from:)` are both written this way today (`fn-spec §4.4`).
- Force-unwrapping an image result is forbidden (`NFR-DATA-004`).

### 1.6 The GCD requirement

**Decided 2026-07-27 — see §1.10.** The comparison below is retained as the reasoning that was in front of the decision, not as an open question.

The brief asks for GCD explicitly. The codebase already uses **Combine** for its networking layer, and SwiftUI's own image loading idiom is `async/await`. These are not equivalent, and picking one silently would be a decision made by omission.

| Concern | GCD | Combine | `async/await` |
|---------|-----|---------|---------------|
| Matches the brief's literal wording | ✅ | ✗ | ✗ |
| Matches the existing networking layer | ✗ | ✅ | ✗ |
| Cancellation (`NFR-PERF-006`) | Manual (`DispatchWorkItem`) | Built in (`AnyCancellable`) | Built in (`Task`) |
| Coalescing duplicate requests | Manual | Manual | Manual |

`NFR-PERF-002` requires *asynchronous*; it does not mandate a mechanism. That was the point: the choice was `FAD-PERF-a`, settled in §1.10 in favour of GCD, as the brief asks. Note that a GCD image loader and a Combine networking layer coexist without contradiction — the two pipelines are independent — so the decision did not force a rewrite of `Services/`, and did not get one.

### 1.7 Acceptance criteria

- Scrolling the full 15-tweet feed, including the 9-image tweet, produces no visible stutter.
- With the network artificially slowed, the list still scrolls at full speed; only the images lag.
- Scrolling to the bottom and back to the top does not re-issue image requests already served (`NFR-PERF-003`).
- No `Data(contentsOf:)` call remains in the codebase.
- Killing mountebank mid-scroll does not hang or crash the app; failed images become placeholders (`NFR-PERF-005`, `NFR-DATA-004`).

### 1.8 Testing and validation considerations

- Instruments → Time Profiler with the main thread filtered, while scrolling: no network or decode frames on the main thread.
- A unit test asserting the image loader invokes its completion on a failure path (`NFR-PERF-005`).
- A unit test asserting a second request for the same URL is served without a second network call (`NFR-PERF-003`).
- Manual: Network Link Conditioner on a slow profile.

### 1.9 Unresolved decisions (Future Architecture Decisions)

- ~~**`FAD-PERF-a`**~~ — **Resolved 2026-07-27 ✅** — §1.10.
- ~~**`FAD-PERF-b`**~~ — **Resolved 2026-07-27 ✅** — §1.11.
- ~~**`FAD-PERF-c`**~~ — **Resolved 2026-07-27 ✅** — §1.12.
- **Assumption carried:** the feed is small enough (22 elements, ≤ 9 images each) that a memory-only cache with no eviction is acceptable for the exercise.

### 1.10 Resolved: concurrency mechanism for the image pipeline (`FAD-PERF-a`) ✅

Ratified **2026-07-27**. `Services/ImageLoader.swift` is **GCD-backed**: a `final class` with a completion-handler interface, three queues, and no `async` keyword in its production path.

**The brief asks for it by name.** `README.md` → *Tech requirements* says *"Utilise GCD for multi-thread operation"*, in the same scored list as *"Layout using swiftUI"* and the dependency prohibition — and the brief states that *"Production and Technical requirements are weighing equally in the final result."* It is phrased as an instruction, not as one of the two items softened to *"appreciated"*. §1.6 exists so that this could not be settled by omission; it was settled by taking the brief at its word.

**How the concurrency is expressed:**

| Job | Mechanism |
|-----|-----------|
| Transport | `URLSession.dataTask`, on `URLSession`'s own queue |
| Guarding the cache bookkeeping | a **serial** `DispatchQueue` — the lock-free way to make `inFlight` safe |
| Decoding and downsampling | a **concurrent** `DispatchQueue` at `.userInitiated` |
| Delivering the result | `DispatchQueue.main.async` (`NFR-PERF-004`) |

The serial state queue also buys an ordering guarantee worth naming: `loadImage` returns its token *before* its own block has run, so a caller can cancel immediately — and because `cancel` is enqueued on the same serial queue, it is guaranteed to run after the registration it cancels.

**An `async/await` version was written first and reverted.** It was shorter — `.task(id:)` in `RemoteImage` collapses start-on-appear, cancel-on-disappear and restart-on-URL-change into one modifier, whereas the GCD form spells all three out as `.onAppear` / `.onDisappear` / `.onChange`. Actor isolation is also a stronger guarantee than a serial queue, because the compiler checks it. Those are the costs of this decision and they are real. They do not outweigh a requirement the brief states in the imperative.

**What the GCD form gains back:** cancellation is now directly testable. `cancel(_:)` is an explicit method with an explicit token, so `test_a_cancelled_request_does_not_call_back` and `test_cancelling_one_of_two_sharers_still_delivers_to_the_other` assert on it head-on. Under structured concurrency the equivalent behaviour was implicit in task cancellation and much harder to pin from a test.

**The networking layer stays Combine.** Three mechanisms across the codebase — Combine for JSON, GCD for images, neither for anything else — is a real inconsistency. The defence is that `ImageLoading` (`arch-spec §8.1`) makes the mechanism an implementation detail of one file, and that the brief names both Combine's absence and GCD's presence as *its* requirements, not ours to reconcile.

**Assumption carried:** cancellation means *this caller stopped caring*, not *deliver nothing to anyone*. A cancelled request receives no callback — that is the point of cancelling — and `NFR-PERF-005`'s "a result on every path" governs requests that are allowed to finish. Requests sharing a download are refcounted so one leaving does not silence the others.

### 1.11 Resolved: cache implementation and eviction (`FAD-PERF-b`) ✅

Ratified **2026-07-27**. `NSCache<NSString, UIImage>`, memory-only, no explicit eviction policy.

**Why.** `NSCache` already evicts under memory pressure and is thread-safe, which is most of what a hand-rolled store would have to reimplement. `URLCache` was the alternative and is rejected because it caches **bytes**: every scroll-back would re-decode and re-downsample, and decoding is the expensive half. Caching the decoded, downsampled `UIImage` is the thing that makes `NFR-PERF-003` worth having.

**The key is URL + pixel size**, not URL alone. The same avatar at 40pt and at 120pt are two legitimately different bitmaps; a URL-only key would serve whichever arrived first and quietly degrade one of them.

**Assumption carried:** disk backing is out of proportion for a 22-element feed with no offline requirement.

### 1.12 Resolved: downsampling primitive (`FAD-PERF-c`) ✅

Ratified **2026-07-27**. `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize`.

**Why.** ImageIO produces the thumbnail without ever decoding the full-size bitmap, which is precisely what `NFR-PERF-007`'s *"before being held in memory"* asks for. A `UIGraphicsImageRenderer` redraw — or the `UIImage.resize(_:)` helper this FAD speculated might serve — decodes first and shrinks after, saving nothing at the moment that matters. `resize(_:)` also force-unwrapped its result, which `NFR-DATA-004` forbids, so reusing it would have imported a crash risk into the commit whose job was removing them. `Extension/UIImage.swift` had no other callers and was deleted.

**Display scale travels with the request** (`loadImage(from:targetSize:displayScale:completion:)`), sourced from `@Environment(\.displayScale)` in `RemoteImage`. Scale is a property of the display the image is bound for, not of the loader; holding it on the loader would also mean reaching for `UIScreen` from a background queue.

---

## 2. Data Resilience (`NFR-DATA`)

### 2.1 Objective

The mock feed is deliberately hostile (`fn-spec §3.3`). The app **MUST** degrade element-by-element, never wholesale: one bad tweet costs one tweet, not the feed.

### 2.2 Scope

- **In scope:** decoding tolerance, HTTP status validation, missing-field fallbacks, image-failure fallbacks, error surfacing.
- **Out of scope (for now):** retry policy, offline caching, and the visual design of the error state — **FAD** (§2.9).

### 2.3 User-visible behaviour

- Malformed feed elements are invisible — no blank cells, no error banners for individual tweets.
- A tweet missing an avatar shows a placeholder avatar; a tweet missing content shows no text row.
- A total request failure produces a visible error state, not a blank screen or a spinner that never stops.

### 2.4 Requirements

| ID | Level | Requirement |
|----|-------|-------------|
| `NFR-DATA-001` | MUST | The feed **MUST** be decoded **element by element**. A element that fails to decode **MUST** be skipped, leaving the remaining elements intact. |
| `NFR-DATA-002` | MUST | Every optional field in the data contract **MUST** be modelled as optional in Swift, and every consumer **MUST** handle its absence. |
| `NFR-DATA-003` | MUST | HTTP responses **MUST** be status-validated before decoding; a non-2xx status **MUST** produce a typed error. *`HttpService.get(url:)` requires an `HTTPURLResponse` in `200..<300` before returning the body, and fails with `NetworkError.httpStatus(_:)` otherwise (§2.12). Pinned offline by `HttpServiceTests`.* |
| `NFR-DATA-004` | MUST | A failed or missing image **MUST** render the placeholder asset (`Constants.DEFAULT_EMPTY_IMAGE`). Force-unwrapping an image result is **forbidden**. *`View/RemoteImage.swift` falls back to the placeholder whenever the loader returns `nil`, and the three force-unwrapping call sites were deleted with the helpers that fed them in commit 03.* |
| `NFR-DATA-005` | MUST | Errors **MUST** be surfaced to the view model as typed values that the view can render (`FR-FEED-004`). ⛔ *Not met — `MomentsViewModel.completionHandler` `print`s the error and discards it.* |
| `NFR-DATA-006` | SHOULD | Diagnostic logging of dropped elements **SHOULD** be available in DEBUG builds (see `fn-spec §8 Q5`). |
| `NFR-DATA-007` | MUST | List identity **MUST** be stable and unique. |

### 2.5 Engineering constraints

- Per-element decoding is implemented with a `Decodable` wrapper that attempts the real type inside a `try?` and stores `nil` on failure, applied as `[FailableDecodable<Tweet>]` — ratified as `FAD-DATA-a` (§2.10). Only the behaviour of `NFR-DATA-001` is mandated; the mechanism is a decision, not a requirement.
- Status validation belongs in `HttpService`, the single `URLSession` boundary (`arch-spec §5`), not duplicated into each feature service.
- The `URLError` failure type in `BaseService.get(url:)` was too narrow to express "HTTP 404"; widening it was part of satisfying `NFR-DATA-003` — ratified as `FAD-DATA-b` (§2.12).

### 2.6 Relationship to the functional specification

`NFR-DATA-001` is the mechanism behind `FR-API-004`; `NFR-DATA-003` behind `FR-API-005`; `NFR-DATA-004` behind `FR-HEADER-002`. The functional spec states *what the user sees*; this section states *what the code must guarantee*. Neither is redundant — a change to one is a signal to re-check the other.

### 2.7 Acceptance criteria

- The feed renders 15 tweets against the unmodified `imposters.ejs`, with the 5 malformed elements absent and no visual artefact where they were.
- Pointing the app at the catch-all 404 path produces an error state, not a decode failure and not an empty success.
- Replacing an image URL with a 404 URL yields the placeholder asset in that slot and leaves the rest of the cell intact.
- Stopping mountebank before launch produces a visible error state within a reasonable timeout.

### 2.8 Testing and validation considerations

- A unit test decoding the committed `WeChatMomentsTests/Resources/Tweets.json` fixture and asserting the malformed elements are dropped while the well-formed ones survive — the count assertion is the whole point (`NFR-TEST-002`).
- A unit test asserting a 404 response produces an error rather than a decoded value, using a mocked `BaseService`.
- A unit test asserting `FR-DATA-001` and `FR-DATA-002`: `sender`-only elements dropped, image-only elements kept.

### 2.9 Unresolved decisions (Future Architecture Decisions)

- **`FAD-DATA-a`:** **Resolved 2026-07-27 ✅** — see §2.10.
- **`FAD-DATA-b`:** **Resolved 2026-07-27 ✅** — see §2.12.
- **`FAD-DATA-c`:** the visual treatment of the error state — inline row, full-screen replacement, or a retry banner. Currently unspecified anywhere.
- **`FAD-DATA-d`:** **Resolved 2026-07-27 ✅** — see §2.11.
- **Assumption:** no retry policy is required for this exercise; a failed request stays failed until the user refreshes.

### 2.10 Resolved: per-element decoding mechanism (`FAD-DATA-a`) ✅

Ratified **2026-07-27**.

A generic failable wrapper, `Models/FailableDecodable.swift`, whose `init(from:)` is `value = try? Wrapped(from: decoder)`. `TweetService` decodes `[FailableDecodable<Tweet>]` and compact-maps `\.value`.

**Why.** Four lines, no decoding mechanics in the service, and it reuses `Decodable` synthesis for `Tweet` itself rather than replacing it. The alternatives — hand-rolling an `UnkeyedDecodingContainer` loop, or decoding to an intermediate `[JSONValue]` and re-encoding — both cost substantially more code and put transport-shaped logic where domain logic belongs (`arch-spec §5.3`).

**Scope of the tolerance.** It is applied at the **feed array only**. `User` and `Comment` have all-optional fields and cannot throw. `Img.url` is non-optional, so a malformed image object would drop its whole tweet rather than just that image. No such element exists in the served feed, and nesting the wrapper inside `images` was judged defensiveness beyond the contract. **Assumption carried:** if the feed ever serves a malformed image object, this is the requirement that bends first.

**Verified:** `TweetDecodingTests` decodes the committed fixture offline — 22 elements in, 17 out, 5 dropped — and `test_strict_decoding_of_the_whole_array_fails` asserts the strict path still fails, which is what makes the lenient path necessary rather than ornamental.

### 2.11 Resolved: stable `Tweet` identity (`FAD-DATA-d`) ✅

Ratified **2026-07-27**.

`Tweet` conforms to `Identifiable` with `let id = UUID()`, excluded from `CodingKeys`. `Tweet` no longer conforms to `Hashable`, and `MomentView` uses `ForEach(tweets)` rather than `ForEach(tweets, id: \.self)`.

**Why.** The payload carries no id, so identity has to be manufactured. A `UUID` assigned at decode time cannot collide, needs no knowledge of the payload's shape, and does not drag `Hashable` conformance onto `User`, `Img`, and `Comment` — three conformances that would exist solely to serve a list key.

**Why not a composite of sender + content + index.** Index is positional. The displayed window moves under pagination (`FR-PAGE-002`) and resets on refresh (`FR-PAGE-004`), so a positional component would change identity for rows that did not change, which is precisely the diffing bug the requirement exists to prevent.

**Assumption carried:** identity is per-decode, not per-tweet-in-the-world. Re-fetching the feed mints new ids. That is correct for `FR-PAGE-004` as currently read (refresh resets the window without re-fetching, `fn-spec §8 Q2`) and would need revisiting only if refresh becomes a re-fetch.

**Verified:** `TweetDecodingTests.test_identity_is_unique_across_identical_content`.

### 2.12 Resolved: the `BaseService` failure type (`FAD-DATA-b`) ✅

Ratified **2026-07-27**.

`Services/NetworkError.swift` replaces `URLError` as the failure type of `BaseService.get(url:)`, and is carried **end-to-end**: `TweetService` and `UserService` publish `AnyPublisher<[Tweet], NetworkError>` and `AnyPublisher<User, NetworkError>` rather than widening back to `any Error`.

```swift
enum NetworkError: Error {
    case transport(URLError)   // no response at all
    case invalidResponse       // not an HTTPURLResponse
    case httpStatus(Int)       // a response, but non-2xx (FR-API-005)
    case decoding(Error)       // a 2xx body the model could not read
}
```

**Why four cases and not one.** The distinctions are the ones a caller acts on differently. "The server is unreachable" is a retry-or-tell-the-user situation; "the server said 404" is a permanent answer about that URL; "the body did not parse" is a client-side contract break. Collapsing them into a single `.failure` would rebuild the exact ambiguity this decision exists to remove — the old code could not tell a 404 from a valid response, which is how `UserServiceTests.test_wrong_url` came to pass by decoding the 404 error body into an all-`nil` `User`.

**Why end-to-end rather than at the seam only.** Keeping `AnyPublisher<[Tweet], Error>` on the feature services would have been a smaller diff, but the view model is the consumer that has to render an error state (`NFR-DATA-005`, `FR-FEED-004`), and it sits at the far end. A typed failure that is widened one hop before its consumer buys nothing. The cost is one `.mapError` per service, which also names the only failure the decoder can produce.

**`Equatable` is deliberately not conformed.** `.transport` and `.decoding` carry payloads that are not `Equatable`, and synthesising equality would mean either dropping those payloads or hand-writing a comparison whose only client is a test assertion. Tests match on the case instead, via the small `XCTAssertHttpStatus` / `XCTAssertIsDecodingFailure` / `XCTAssertIsTransportFailure` helpers in `WeChatMomentsTests/Support/`.

**Assumption carried:** `.httpStatus` discards the response body. The catch-all stub returns `{"error": "User not found"}` alongside its 404, and nothing in the app displays it. If an error state ever needs to show a server-supplied message, this is the case that gains an associated value.

**Verified:** `HttpServiceTests` asserts 200 → data, 404/500/304 → `.httpStatus` with the right code, and a `URLError` → `.transport`, all against a stubbed `URLProtocol` with no network. `TweetServiceTests` and `UserServiceTests` assert the same errors survive the decode stage without being reclassified.

---

## 3. Layout Adaptivity (`NFR-LAYOUT`)

### 3.1 Objective

The brief requires *"layout on all kinds of iOS device screen and orientation."* The layout **MUST** derive from available space rather than from assumed device dimensions.

### 3.2 Scope

- **In scope:** width-independent layout, orientation changes, the image grid's response to available width, text wrapping and expansion.
- **Out of scope (for now):** iPad-specific layouts, split view, Stage Manager, and Dynamic Type beyond the `SHOULD` in `NFR-LAYOUT-005`.

### 3.3 User-visible behaviour

- Rotating the device reflows the feed; nothing clips, overlaps, or leaves a gap at the trailing edge.
- The image grid keeps its cells square and its columns aligned at every width.
- Long tweet content wraps rather than truncating (`FR-TWEET-003`).

### 3.4 Requirements

| ID | Level | Requirement |
|----|-------|-------------|
| `NFR-LAYOUT-001` | MUST | No layout **MUST** depend on a hard-coded screen width or a specific device size. Sizes come from the layout system (`GeometryReader`, `.frame(maxWidth:)`, grid sizing), not from constants. |
| `NFR-LAYOUT-002` | MUST | Rotation **MUST** reflow the header and the feed without clipping or overlap. ⚠️ *`HeaderView` currently pins its height to a fixed `370` and offsets the avatar/nick by arithmetic against that constant; this survives width changes but is fragile under any height change.* |
| `NFR-LAYOUT-003` | MUST | The image grid's cell size **MUST** derive from available width (`FR-TWEET-010`), preserving square cells and consistent gutters. ⛔ *Not met — `TweetView` frames cells at `Constants.IMAGE_SIZE * 2` regardless of available width.* |
| `NFR-LAYOUT-004` | MUST | Text **MUST** wrap to unlimited lines where the design calls for full content, and truncate deliberately (with a stated mode) only where it does not — the header nick truncates by design. |
| `NFR-LAYOUT-005` | SHOULD | The layout **SHOULD** tolerate Dynamic Type at least through the default accessibility sizes. Deliberately a `SHOULD`: the exercise does not require it, and hard-coded point sizes in `Config/Constant.swift` currently prevent it. |
| `NFR-LAYOUT-006` | SHOULD | Safe areas **SHOULD** be respected for interactive and textual content. *`MomentView` currently applies a blanket `.ignoresSafeArea()`, which is intentional for the full-bleed header but pushes content under the status bar.* |

### 3.5 Engineering constraints

- Layout constants in `Config/Constant.swift` describe *intrinsic* sizes (an avatar is 40×40 regardless of device). They **MUST NOT** be used to derive container widths.
- SwiftUI's `LazyVGrid` with adaptive or flexible `GridItem`s satisfies `NFR-LAYOUT-003` without manual arithmetic.

### 3.6 Acceptance criteria

- The feed renders correctly on the smallest and largest current iPhone simulators, portrait and landscape, with no clipping and no horizontal scroll.
- The 9-image tweet forms a clean 3×3 grid at every tested width.
- Rotating mid-scroll preserves scroll position approximately and does not corrupt the layout.

### 3.7 Testing and validation considerations

- Manual pass across two simulator sizes × two orientations.
- SwiftUI previews pinned to several device sizes for `TweetView` and `HeaderView`.
- A UI test that rotates the device and asserts key elements remain hittable.

### 3.8 Unresolved decisions (Future Architecture Decisions)

- **`FAD-LAYOUT-a`:** whether `HeaderView`'s fixed `370` height becomes proportional (e.g. a fraction of width) or stays fixed with only the overlay positioning made relative.
- **`FAD-LAYOUT-b`:** whether Dynamic Type is pursued at all for this exercise (`NFR-LAYOUT-005`); doing so implies replacing the point sizes in `Config/Constant.swift` with text styles.

---

## 4. Testability (`NFR-TEST`)

### 4.1 Objective

The brief states *"Unit tests are appreciated"* and *"Functional programming is appreciated."* Both are architecture requirements before they are test requirements: code that cannot be constructed without a network cannot be unit tested.

### 4.2 Scope

- **In scope:** dependency injection seams, offline unit tests, fixture usage, the unit/integration split, purity of transforms.
- **Out of scope (for now):** coverage targets, snapshot testing, and CI configuration — **FAD** (§4.9).

### 4.3 Requirements

| ID | Level | Requirement |
|----|-------|-------------|
| `NFR-TEST-001` | MUST | Every dependency that performs I/O **MUST** be injectable behind a protocol. *`TweetService` and `UserService` take `init(httpService: BaseService = HttpService())`; `HttpService` already took `init(urlSession:)`. `ImageLoader` takes `init(urlSession:)` and reaches the view tree as `any ImageLoading` through `EnvironmentValues.imageLoader`, constructed once in `WeChatMomentsApp` — environment rather than a defaulted constructor argument, which would have built a separate loader per view and destroyed the shared cache. `MomentsViewModel` still constructs both network services internally — that is `arch-spec §4.2`'s remaining gap, not this one.* |
| `NFR-TEST-002` | MUST | Unit tests **MUST NOT** require a live network or a running mountebank instance. *The full suite passes with mountebank stopped; the three genuine integration tests skip (§4.8).* |
| `NFR-TEST-003` | MUST | The committed fixture `WeChatMomentsTests/Resources/Tweets.json` **MUST** be the offline source for decoding tests. |
| `NFR-TEST-004` | MUST | Tests that genuinely require mountebank **MUST** be identifiable as integration tests — by naming, by target, or by a documented `-only-testing` selector — so that the offline suite can be run alone. |
| `NFR-TEST-005` | MUST | Pagination logic (`FR-PAGE-*`) **MUST** be testable without instantiating a view. This follows from it living in the view model (`arch-spec §7`). |
| `NFR-TEST-006` | SHOULD | Data transforms — filtering (`FR-DATA-*`), paging windows, grid-column derivation — **SHOULD** be pure functions over their inputs, so they can be tested without any object graph. This is the concrete form the brief's "functional programming is appreciated" takes. |
| `NFR-TEST-007` | SHOULD | Mocks **SHOULD** live in a single `Mocks/` folder, guarded by `#if DEBUG`, and be shared between SwiftUI previews and tests. |
| `NFR-TEST-008` | SHOULD | The scenarios in `fn-spec §7` **SHOULD** each have a corresponding automated test where the scenario is observable without a device. |

### 4.4 Engineering constraints

- Constructor injection with a **default argument** (`init(httpService: BaseService = HttpService())`) satisfies `NFR-TEST-001` with no change to any call site. *Applied in commit 02.*
- `WeChatMomentsTests/Config/TestDataConfig.swift` still holds inline JSON dictionaries (including one keyed `profile-image`) that are largely unused — only its `USER` and `URL_HOST` constants are read. Either it becomes the mock's data source or it is deleted; leaving dead fixtures alongside live ones is worse than either (`FAD-TEST-c`).
- `WeChatMomentsUITests/WeChatMomentsUITests.swift` is an unmodified Xcode template stub with empty test bodies. It asserts nothing and **SHOULD** be replaced or removed. *Its unit-target counterpart was deleted in commit 02.*

### 4.5 Acceptance criteria

- `xcodebuild test` passes with **mountebank stopped**, excluding any explicitly-marked integration tests.
- A decoding test reads `Tweets.json` from the test bundle and asserts the displayable-count arithmetic of `fn-spec §3.3`.
- A view-model test drives initial load → append → append → refresh against a mocked service and asserts window sizes 5 → 10 → 15 → 5.
- No test contains a `localhost` URL outside the integration set.

### 4.6 Testing and validation considerations

- Run the offline suite with the network disabled entirely, not merely with mountebank stopped — a test that quietly depends on the remote image host will pass locally and fail in CI.
- The old `test_wrong_url` tests asserted against the catch-all 404 stub. With `NFR-DATA-003` landed they became genuine status-validation tests and moved to the mocked suite; one live-404 check remains in `HttpServiceIntegrationTests`, which is the only place the 404 is real rather than scripted.

### 4.7 Unresolved decisions (Future Architecture Decisions)

- **`FAD-TEST-a`:** **Resolved 2026-07-27 ✅** — see §4.8.
- **`FAD-TEST-b`:** whether to adopt Swift Testing (`@Test`/`#expect`) or stay on XCTest. The project is on XCTest; the deployment target (iOS 17.2) permits either.
- **`FAD-TEST-c`:** the fate of `TestDataConfig.swift` — promote to the canonical mock fixture, or delete in favour of `Tweets.json`.

### 4.8 Resolved: separating the integration tests (`FAD-TEST-a`) ✅

Ratified **2026-07-27**.

Integration tests are identified **by folder and by class name** — `WeChatMomentsTests/Integration/HttpServiceIntegrationTests.swift` — and each opens with:

```swift
try XCTSkipUnless(Mountebank.isReachable, "mountebank is not running on \(TestDataConfig.URL_HOST).")
```

With mountebank stopped the default `xcodebuild test` invocation reports **0 failures and 3 skips**. With it running, all three execute. No `-only-testing` selector is needed for the offline run, though `-only-testing:WeChatMomentsTests/HttpServiceIntegrationTests` selects the integration set when the mock is up.

**Why this and not a test plan.** A test plan is the cleaner expression and would make the split declarative rather than conventional. It requires a shared scheme, which the project does not have — `FAD-ARCH-b`, deliberately deferred. Resolving `FAD-TEST-a` this way keeps the two decisions independent: if `FAD-ARCH-b` is later taken up, converting these tests to a plan is a mechanical change and the folder is already the right shape for it.

**Why not a fourth target.** Strongest isolation, but creating a target is a large hand-edit to `project.pbxproj` — precisely the class of risk `FAD-ARCH-a` (`arch-spec §2.5`) was resolved to eliminate. Disproportionate for three tests.

**The cost, stated plainly.** A skip is quieter than a failure. If mountebank is down, three tests silently do not run, and a reader skimming "TEST SUCCEEDED" learns less than they would from a red build. That is the deliberate trade: `NFR-TEST-002` says the offline suite must pass, and a test that fails because a server is missing is exactly what that requirement forbids. The mitigation is that the skip is reported per-test with its reason, and that everything these tests would catch about *our* code is already covered offline — what they add is confirmation that `imposters.ejs` still serves what the app expects.

**Assumption carried:** the reachability probe is a 2-second `URLSession` request to `localhost:2727`. On loopback a refused connection returns immediately, so the probe is effectively free when the server is down. A *hung* mountebank — accepting connections but never answering — would cost 2 seconds per test rather than being reported as a failure.

**Verified:** the full suite, mountebank stopped — 28 passed, 0 failed, 3 skipped. The same suite with mountebank running — 31 passed, 0 skipped.

---

## 5. Acceptance Matrix

Every row must pass before the app is considered complete.

| # | Device | Orientation | Backend state | Must verify |
|---|--------|-------------|---------------|-------------|
| 1 | Small iPhone | Portrait | mountebank up | 5 tweets initially; grid square; header complete |
| 2 | Small iPhone | Landscape | mountebank up | Reflow, no clipping, 3×3 grid intact |
| 3 | Large iPhone | Portrait | mountebank up | Full pagination cycle 5 → 10 → 15 → refresh → 5 |
| 4 | Large iPhone | Landscape | mountebank up | As row 2 |
| 5 | Any | Portrait | mountebank **down** | Visible error state; no hang; no crash |
| 6 | Any | Portrait | mountebank up, image host unreachable | Placeholders in every image slot; text and layout unaffected |
| 7 | Any | Rotate mid-scroll | mountebank up | Layout survives; scroll position approximately preserved |

Cross-cutting checks for every row: no main-thread stalls while scrolling; no malformed element visible; no force-unwrap crash; memory does not grow unboundedly while scrolling the feed repeatedly.

---

## 6. Consolidated Open Questions

| Ref | Area | Question |
|-----|------|----------|
| ~~`FAD-PERF-a`~~ | Concurrency | GCD, Combine, or `async/await` for the image pipeline? The brief says GCD; the codebase says Combine. **Resolved 2026-07-27 ✅** — §1.10, in favour of **GCD**, as the brief asks. |
| ~~`FAD-PERF-b`~~ | Caching | Cache implementation and eviction policy; memory-only or disk-backed. **Resolved 2026-07-27 ✅** — §1.11. |
| ~~`FAD-PERF-c`~~ | Images | Downsampling primitive — `ImageIO` thumbnails vs. the existing `UIImage.resize(_:)`. **Resolved 2026-07-27 ✅** — §1.12. |
| ~~`FAD-DATA-a`~~ | Decoding | Mechanism for per-element lenient decoding. **Resolved 2026-07-27 ✅** — §2.10. |
| ~~`FAD-DATA-b`~~ | Errors | Replacement error type for `URLError` in `BaseService`, able to express HTTP status. **Resolved 2026-07-27 ✅** — §2.12. |
| `FAD-DATA-c` | Errors | Visual treatment of the error state. |
| ~~`FAD-DATA-d`~~ | Identity | Stable identity for `Tweet` — the payload carries no id. **Resolved 2026-07-27 ✅** — §2.11. |
| `FAD-LAYOUT-a` | Layout | Whether `HeaderView`'s fixed 370pt height becomes proportional. |
| `FAD-LAYOUT-b` | Layout | Whether Dynamic Type is pursued at all. |
| ~~`FAD-TEST-a`~~ | Testing | How integration tests are separated from the offline suite. **Resolved 2026-07-27 ✅** — §4.8. |
| `FAD-TEST-b` | Testing | Swift Testing vs. XCTest. |
| `FAD-TEST-c` | Testing | Fate of `TestDataConfig.swift`. |

---

*All requirement IDs (`NFR-PERF-*`, `NFR-DATA-*`, `NFR-LAYOUT-*`, `NFR-TEST-*`) are stable and may be referenced by architecture, implementation, and test documents. This document defines requirements only; no production code is affected by it.*
