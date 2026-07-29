# WeChat Moments — Architecture Specification

> **Purpose:** define how the app is structured — its layers, their responsibilities, the flow of dependencies and data, the folder layout, and the naming and testing conventions. This document defines *architecture*, not visual or behavioural detail (see [`functional-specification.md`](./functional-specification.md)) and not quality requirements (see [`non-functional-requirements.md`](./non-functional-requirements.md)); it references both where they constrain structure.
>
> **Scope reminder:** this is a **single static screen** — a profile header and a paginated feed, with no navigation, no writes, and no persistence. The architecture is deliberately **proportional** to that scope. Every guideline below states not only *what* to do but *when the abstraction is worth it*. Layers this project does **not** have are enumerated in §1.2, with reasons.
>
> **Ratification, not invention.** The codebase already embodies architectural decisions — MVVM, Combine, a `BaseService` seam, a `Config/` constants layer. This document ratifies and sharpens those rather than proposing a green-field alternative. Where the code does not live up to the architecture it already implies, that gap is named explicitly with **⛔**.

---

## 1. Architecture Overview

### 1.1 The shape

**MVVM** over a **Combine** networking stack, with dependencies supplied by constructor injection.

```
   ┌──────────────┐   renders / sends intents   ┌────────────────────┐
   │  SwiftUI     │ ──────────────────────────▶ │    ViewModel       │
   │    View      │ ◀────────────────────────── │  (ObservableObject)│
   └──────────────┘   observes @Published state └─────────┬──────────┘
          │                                                │ requests
          │ asks for images                                 ▼
          │                                       ┌────────────────────┐
          │                                       │  Feature Service   │
          │                                       │ Tweet… · User…     │
          ▼                                       └─────────┬──────────┘
   ┌──────────────┐                                          │ get(url:)
   │ Image Loader │                                          ▼
   │  (+ cache)   │                               ┌────────────────────┐
   └──────┬───────┘                               │  BaseService       │
          │                                       │  ← HttpService     │
          │  ───────── network ─────────────────▶ └─────────┬──────────┘
                                                             │ URLSession
                                                             ▼
                                                  ┌────────────────────┐
                                                  │  mountebank mock   │
                                                  │  localhost:2727    │
                                                  └────────────────────┘
```

Key properties:

- **Views are declarative and passive.** They render published state and forward user intents. They hold no business logic and perform no filtering, paging, or formatting.
- **The view model owns presentation state and logic** — the full in-memory feed, the displayed window, the loading flag, and the error state.
- **`HttpService` is the only type that touches `URLSession`.** Feature services compose it and decode; nothing else knows the transport exists.
- **Abstractions exist only where they buy testability.** `BaseService` earns its place because `NFR-TEST-001` demands it. Value types, constants, and the single screen are used concretely.
- Data flow is **unidirectional**: `user event → view calls a view-model method → view model mutates @Published state → SwiftUI re-renders`.

### 1.2 Layers this project deliberately does not have

| Absent layer | Why |
|--------------|-----|
| **Coordinator / router** | There is one screen and no navigation. A coordinator would abstract a decision that is never made. Introduce one only if a second destination appears. |
| **Design system (tokens + components)** | The app has one screen's worth of styling. `Config/Constant.swift` holds the dimensions and font sizes; that is the proportional answer. A two-tier token/component system would be ceremony without reuse. |
| **Repository layer** | There is no persistence and no second data source. Feature services *are* the data layer. |
| **DI container** | Three dependencies, one composition point. Constructor injection with default arguments is sufficient (§6). |

Adding any of these requires a stated reason and a spec change — not a passing preference.

---

## 2. Project Folder Structure

### 2.1 Current layout (as on disk)

```
WeChatMoments/
├── WeChatMomentsApp.swift      # @main App → MomentView(), injects the shared ImageLoader
├── MomentView.swift            # ⚠️ root screen, sitting OUTSIDE View/
├── Models/
│   ├── Tweet.swift · User.swift · Comment.swift · Img.swift   # one type per file
│   └── FailableDecodable.swift # per-element decoding wrapper (NFR-DATA-001)
├── View/
│   ├── HeaderView.swift        # profile banner + avatar + nick
│   ├── TweetView.swift         # tweet cell
│   ├── ImageGridView.swift     # the 0-to-9 image grid (fn-spec §5, FR-TWEET-004/005)
│   ├── RemoteImage.swift       # async image view owning its @State image + token (§8.4)
│   ├── CommentBlockView.swift  # hides itself when comments are absent or empty (FR-TWEET-006)
│   ├── CommentRowView.swift    # one comment line
│   ├── FeedErrorView.swift     # the feed's error state (FR-FEED-004, FAD-DATA-c)
│   └── FooterView.swift        # the hairline between cells (FR-TWEET-008)
├── ViewModel/
│   ├── MomentsViewModel.swift
│   ├── Loadable.swift          # one request's lifecycle as a value (§4.2)
│   ├── TweetFilter.swift       # pure display filter (FR-DATA-001/002, NFR-TEST-006)
│   └── ImageGridLayout.swift   # pure grid-layout derivation (fn-spec §5, NFR-TEST-006)
├── Services/
│   ├── HttpService.swift       # BaseService protocol + HttpService
│   ├── NetworkError.swift      # the single failure type (FAD-DATA-b)
│   ├── TweetService.swift
│   ├── UserService.swift
│   └── ImageLoader.swift       # ImageLoading protocol + GCD-backed cached loader (§8)
├── Mocks/                      # #if DEBUG — shared by previews and tests
│   ├── MockBaseService.swift
│   └── MockImageLoader.swift
├── Config/
│   ├── Constant.swift          # enum Constants (⚠️ SCREAMING_SNAKE members)
│   └── UrlConstant.swift       # enum UrlConstant
├── Extension/                  # ⚠️ singular
│   ├── Color.swift · String.swift
│   ├── User+DisplayName.swift  # the sender-name fallback (FR-TWEET-001/007)
│   └── EnvironmentValues+ImageLoader.swift   # the ImageLoading injection point
├── Assets.xcassets/
└── Preview Content/
```

### 2.2 Target layout

```
WeChatMoments/
├── App/
│   ├── WeChatMomentsApp.swift  # @main App
│   └── RootView.swift          # composition root: builds the view model, hosts MomentsView
├── Features/
│   └── Moments/
│       ├── MomentsView.swift       # root screen (renamed from MomentView, now plural)
│       ├── MomentsViewModel.swift
│       ├── HeaderView.swift
│       ├── TweetView.swift
│       ├── CommentBlockView.swift
│       ├── CommentRowView.swift
│       ├── FooterView.swift
│       └── Support/
│           ├── TweetFilter.swift       # pure display filter (NFR-TEST-006)
│           └── ImageGridLayout.swift   # pure grid-column derivation (NFR-TEST-006)
├── View/
│   └── RemoteImage.swift       # feature-agnostic: any URL, any size (§8.4)
├── Models/
│   ├── Tweet.swift · User.swift · Comment.swift · Img.swift   # one type per file
│   └── FailableDecodable.swift     # per-element decoding wrapper (FAD-DATA-a)
├── Services/
│   ├── HttpService.swift       # BaseService protocol + HttpService
│   ├── TweetService.swift
│   ├── UserService.swift
│   └── ImageLoader.swift       # ImageLoading protocol + GCD-backed cached loader (§8)
├── Config/
│   ├── Constants.swift
│   └── UrlConstant.swift
├── Extensions/
│   └── Color+Moments.swift · String+Height.swift · EnvironmentValues+ImageLoader.swift
├── Mocks/                      # #if DEBUG — shared by previews and tests
│   ├── MockBaseService.swift
│   └── MockImageLoader.swift
├── Assets.xcassets/
└── Preview Content/
```

### 2.3 Migration rule

**Files migrate when the feature that touches them is next modified. There is no big-bang move.**

The rule is about diff readability, not mechanics: a commit that moves files *and* changes them is reviewable; a commit that only shuffles paths is noise. Since `FAD-ARCH-a` was ratified (§2.5) the project uses synchronized folder groups, so a move is a pure filesystem operation with no `project.pbxproj` edit and no risk of corrupting the project.

Consequences:

- Adding, moving, renaming, or deleting a file is done on disk. Xcode picks it up automatically; `project.pbxproj` is not touched and must not appear in the diff.
- A pull request that only moves files is still a bad trade — bundle the move with the work that motivates it.

### 2.5 Resolved: synchronized folder groups (`FAD-ARCH-a`) ✅

Ratified **2026-07-27**.

The project was migrated from `objectVersion = 56` (explicit file listing) to `objectVersion = 77` with a `PBXFileSystemSynchronizedRootGroup` per target.

**Why.** Under the old format each new file cost three coordinated pbxproj edits — a `PBXFileReference`, a `PBXGroup.children` entry, and a `PBXBuildFile` plus its `PBXSourcesBuildPhase` entry. The implementation sequence that follows adds roughly fifteen files, so the old format meant ~45 chances to corrupt a file that nothing but Xcode validates. The migration converts that into one contained, immediately-verifiable risk.

**What it cost.** `project.pbxproj` shrank from 33.1 KB to 20.0 KB — all of it bookkeeping that the filesystem already expresses. Requires Xcode 16+; this project builds on Xcode 26.2.

**Assumptions carried:** every file inside `WeChatMoments/`, `WeChatMomentsTests/`, and `WeChatMomentsUITests/` belongs to that target. This holds today. A file that must be excluded needs a `PBXFileSystemSynchronizedBuildFileExceptionSet`, which is the one thing the old format expressed more directly.

**Verified:** clean build compiles all 17 source files, and the test suite produces results identical to the pre-migration baseline — the same two pre-existing failures, unchanged.

### 2.4 Rules

- A feature folder contains **only that feature's** view, view model, subviews, and feature-local support types.
- Shared services, models, config, and extensions live in their own top-level folders and **MUST NOT** depend on any feature.
- Files are named for the single type they contain (§11).

---

## 3. Layer and Component Responsibilities

| Component | Owns | Must NOT |
|-----------|------|----------|
| **SwiftUI View** | Layout, rendering, gesture and scroll wiring, forwarding intents to the view model, reading published state. | Business rules, filtering, pagination arithmetic, network calls, constructing its own dependencies, force-unwrapping. |
| **View Model** | Presentation state (`@Published`), the in-memory feed, the displayed window, loading and error state, orchestration of services. | Import SwiftUI view types, know about `URLSession`, construct concrete services internally (`NFR-TEST-001`). |
| **Feature Service** (`TweetService`, `UserService`) | Building the endpoint URL, invoking `BaseService`, decoding into models, per-element tolerance (`NFR-DATA-001`). | Touch `URLSession` directly, hold state, know about views or view models. |
| **`HttpService` / `BaseService`** | The single `URLSession` boundary; status validation (`NFR-DATA-003`); returning raw `Data` or a typed error. | Decode domain types, know any endpoint, know any feature. |
| **`ImageLoader`** | Asynchronous image fetch, caching, cancellation, downsampling (`NFR-PERF-002/003/006/007`). | Return synchronously; invoke its callback on only one branch; force-unwrap. |
| **Model** | The decoded shape of the API payload, including `CodingKeys` where the wire format differs (`FR-API-001`). | Contain presentation logic, formatting, or view-specific derived values. |
| **Config** | Endpoint construction and intrinsic layout/typography constants. | Hold mutable state or derive container sizes (`NFR-LAYOUT-001`). |
| **Extensions** | Small, general-purpose helpers on framework types. | Encode feature-specific behaviour — that belongs in `Features/…/Support/`. |
| **Mocks** | `#if DEBUG` test doubles for every protocol, with call recording. | Ship in release builds; contain production logic. |
| **Composition Root** (`RootView`) | Constructing and wiring services → view model → view. | Contain business or presentation logic. |

---

## 4. MVVM Responsibilities

### 4.1 View

- A `struct: View` receiving what it needs by `init`; the root view owns its view model as **`@StateObject`**, subviews receive plain values or `@ObservedObject`.
- *`MomentView` declared `@ObservedObject var momentsViewModel = MomentsViewModel()` until commit 06. With `@ObservedObject` SwiftUI does not own the object's lifetime, so the view model was recreated on every structural re-render of the parent — losing the loaded feed and, once it existed, the pagination window. It is now `@StateObject private var`, and it landed in the same commit as the window rather than after it, because the two defects are only harmful together.*
- Decomposed into small `private` subviews; each receives only the data it needs.
- Calls **intent methods** on the view model (`viewModel.loadInitialData()`, `viewModel.loadNextPage()`, `viewModel.refresh()`), never mutating its state directly.
- Owns no filtering, no paging arithmetic, and no image-fetch orchestration beyond asking the loader for a URL.

### 4.2 View Model

- An `ObservableObject` (a `final class`), injected with its services as **protocols**.
- Owns:
  - the **full** decoded feed, filtered per `FR-DATA-001/002` at the point of entry;
  - the **displayed window** (`FR-PAGE-*`), as derived state — see §7;
  - the loading flag and the error state.
- *`MomentsViewModel.loadData()` toggled `showIndicator` twice in immediate succession — before either request had completed — and each completion handler toggled it once more, so the flag tracked no in-flight work at all (`FR-FEED-003`). Resolved in commit 06 with the **explicit state enum** this section offered, `ViewModel/Loadable.swift`, held **once per request** rather than once per screen: `feed: Loadable<[Tweet]>` and `profile: Loadable<User>`. The indicator is derived from the pair and the error state is the `.failed` case, which is the `NFR-DATA-005` home this section predicted. Per-request rather than per-screen is what makes `FR-FEED-005` structural — a completion can only write its own property, so neither failure has a path to the other.*
- *It also constructed `TweetService()` and `UserService()` as stored property initialisers, so nothing could inject a mock (`NFR-TEST-001`). It now takes `init(tweetService:userService:)` with the §6 defaulted-argument pattern. No protocol was introduced for either service: they perform no I/O themselves, and `MockBaseService` one hop down is what the tests need.*
- Never imports SwiftUI view types and never performs navigation.

### 4.3 View ⇄ ViewModel contract

| Direction | Mechanism |
|-----------|-----------|
| View → ViewModel | Named intent methods. No setters, no direct state mutation. |
| ViewModel → View | `@Published` properties only, published on the main thread (`NFR-PERF-004`). |
| Errors | A published, typed error state the view renders (`NFR-DATA-005`) — never a `print`. |

---

## 5. Networking and Data Flow

### 5.1 The seam

`BaseService` is the project's single abstraction over the network:

```swift
protocol BaseService {
    func get(url: URL) -> AnyPublisher<Data, NetworkError>
}
```

`HttpService` is its only production implementation and the only type in the app that references `URLSession`. Feature services compose it, build their URL from `UrlConstant`, and decode.

### 5.2 Two defects the seam used to carry

Both were fixed in commit 02; the history is retained because the shape of the fix is the reason the seam is now worth having.

**The injection point did not exist.** `TweetService` and `UserService` both declared `private var httpService: BaseService` — correctly typed against the protocol — and then hard-coded `self.httpService = HttpService()` in a no-argument `init()`. The protocol was decorative: no test, preview, or alternate configuration could supply a different implementation. Both now take a default-argument initialiser, which changed no existing call site:

```swift
init(httpService: BaseService = HttpService()) {
    self.httpService = httpService
}
```

**The failure type could not express HTTP.** `get(url:)` did `.map(\.data)`, discarding the `HTTPURLResponse` entirely, so a 404 body was delivered as success `Data` and handed to the decoder (`FR-API-005`, `NFR-DATA-003`). The fix required both status validation *and* a failure type wider than `URLError`, which has no representation for "the server said 404". `Services/NetworkError.swift` is that type and is carried end-to-end — see `FAD-DATA-b` (`nfr §2.12`).

### 5.3 Decoding responsibility

Decoding belongs to the **feature service**, not to `HttpService`. This keeps the transport ignorant of domain types and gives each service a natural home for its own tolerance rules — in particular the per-element lenient decoding of the feed (`NFR-DATA-001`), which applies to `TweetService` and not to `UserService`.

A decode failure is *also* a `NetworkError` — `.decoding(Error)` — so a feature service publishes `AnyPublisher<[Tweet], NetworkError>` rather than widening back to `any Error`. The view model therefore receives one typed failure for the whole pipeline, which is what `NFR-DATA-005` needs somewhere to land.

---

## 6. Dependency Management and Dependency Inversion

- **Constructor injection only.** No service locators, no singletons for anything injectable, no DI container.
- **Default arguments** supply the production implementation, so injection costs nothing at call sites (§5.2).
- **Protocols are introduced where they buy testability or decoupling** — currently `BaseService`, and `ImageLoading` once §8 lands. Nothing else needs one.
- **Do not abstract for its own sake.** A protocol with exactly one implementation and no test double is dead weight. Conversely, a protocol whose only implementation is hard-coded into its consumer — the current `BaseService` situation — is worse than no protocol, because it advertises a flexibility that does not exist.
- `ImageHelper.shared` was a singleton. It was replaced in commit 03 by an injected `ImageLoading` (§8), as `NFR-TEST-001` requires; a singleton is acceptable only for genuinely process-wide, stateless utilities, which a cache is not. The injection runs through `EnvironmentValues.imageLoader` rather than a constructor argument, because `RemoteImage` sits several levels below the composition root and a defaulted argument would have built a fresh loader — and therefore a fresh, empty cache — per view.

---

## 7. Pagination Design

Pagination is the largest unbuilt piece of the app (`FR-PAGE-*`) and its placement determines whether it can be tested.

### 7.1 State

The view model holds two things:

| State | Meaning |
|-------|---------|
| **The full feed** | Every displayable tweet, decoded once and filtered once (`FR-FEED-001`, `FR-DATA-004`). Never re-fetched by scrolling. |
| **The displayed count** | How many of them are currently shown. Starts at 5; grows by 5; resets to 5. |

The displayed window is a **derived value**, not a second stored array: `Array(allTweets.prefix(displayedCount))`. Storing it separately introduces a synchronisation bug for no benefit.

*Both landed in commit 06, as `feed: Loadable<[Tweet]>` and `@Published private(set) var displayedCount`, with `displayedTweets` the derived prefix. `prefix` clamps on its own, so a feed shorter than a page needs no special case (`fn-spec §8 Q6`).*

### 7.2 Why the view model and not the view

- `FR-PAGE-005` requires it, and `NFR-TEST-005` depends on it: a window computed inside `body` cannot be asserted without rendering.
- The reset-on-refresh contract (`FR-PAGE-004`) is a state transition, and state transitions belong with state.

### 7.3 Contract

| Intent | Effect |
|--------|--------|
| `loadInitialData()` | Fetch, filter, store the full feed; set displayed count to 5. *Built in commit 06. Guarded on the `.idle` state so a repeated `.onAppear` cannot re-request (`FR-FEED-002`).* |
| `loadNextPage()` | `displayedCount = min(displayedCount + 5, allTweets.count)`. Idempotent at the end of the list (`FR-PAGE-003`); no network. *Built in commit 07, exactly as written here. The `min` is load-bearing rather than defensive: it is what allows the view trigger to fire repeatedly without a guard of its own.* |
| `refresh()` | Reset displayed count to 5. Whether it also re-fetches is `fn-spec §8 Q2`. *Not yet built — `FR-PAGE-004`.* |

The page size (5) is a named constant in `Config/Constants.swift`, not a literal scattered across the view model. *`Constants.PAGE_SIZE`, added in commit 06; it keeps the file's existing `SCREAMING_SNAKE` convention rather than pre-empting the §9 rename.*

### 7.4 Trigger

The view detects "scrolled to the bottom" and calls `loadNextPage()`. The detection mechanism — `onAppear` on the last row, a scroll-position reader, or `List`'s own lazy loading — is a view concern and is not specified here. The exact trigger point is `fn-spec §8 Q1`.

*Chosen in commit 07, once `§8 Q1` was resolved: `List`'s own laziness plus an `.onAppear` on the last displayed row, dispatched through a named `appendPageIfLast(_:)` rather than inline in `body`. The view still performs no paging arithmetic — it decides* when*, the view model decides* what *(`FR-PAGE-005`). The scroll-geometry alternatives were not weighed on merit: `.onScrollGeometryChange` and `scrollPosition(_:)` are iOS 18+ and this project targets iOS 17.2, so measuring the offset by hand in a `GeometryReader` was the only form they could have taken.*

---

## 8. Image Loading Architecture

`Utils/ImageHelper.swift` was 25 lines and structurally unsound: a synchronous overload that returned `nil` unconditionally, an asynchronous overload that blocked on `Data(contentsOf:)` and never called back on failure, no cache, and a `forSize:` parameter it ignored. It was not patchable; it was deleted and replaced in commit 03.

### 8.1 The seam

```
Services/ImageLoader.swift
    protocol ImageLoading: AnyObject { … }      # injected via EnvironmentValues.imageLoader
    struct ImageRequestToken                    # opaque cancellation handle
    final class ImageLoader: ImageLoading       # cache + GCD fetch + coalescing + cancellation
Extension/EnvironmentValues+ImageLoader.swift   # the injection point
View/RemoteImage.swift                     # the only consumer (§8.4)
Mocks/MockImageLoader.swift                # #if DEBUG
```

The surface is two methods:

```swift
@discardableResult
func loadImage(from urlString: String?, targetSize: CGSize, displayScale: CGFloat,
               completion: @escaping (UIImage?) -> Void) -> ImageRequestToken?
func cancel(_ token: ImageRequestToken)
```

`UIImage?` rather than a typed error, because a missing avatar is a placeholder, not an error state — the distinction `NetworkError` exists to draw for the feed does not apply here. The returned token is `nil` when there is nothing left to cancel: a cache hit and an unusable URL both answer synchronously, inside the call. `displayScale` arrives with the request instead of living on the loader: it belongs to the display the image is bound for, and holding it on the loader would also mean reaching for `UIScreen` from a background queue.

Internally, three queues: `URLSession`'s own for transport, a **serial** queue guarding the in-flight table (the lock-free way to make it safe), and a **concurrent** `.userInitiated` queue for ImageIO decoding. Completions land via `DispatchQueue.main.async` (`NFR-PERF-004`).

### 8.2 Requirements it must satisfy

| Requirement | What it forces |
|-------------|----------------|
| `NFR-PERF-002` | Asynchronous only. No synchronous image API may exist. |
| `NFR-PERF-003` | A cache keyed by URL, consulted before the network. |
| `NFR-PERF-005` | A result delivered on **every** path, including failure and invalid URL. |
| `NFR-PERF-006` | Cancellation for off-screen cells; coalescing of duplicate in-flight requests. |
| `NFR-PERF-007` | Honour `forSize:` by downsampling. |
| `NFR-DATA-004` | Failure yields the placeholder asset, never a force-unwrap. |
| `NFR-TEST-001` | Injected as a protocol, not reached through a singleton. |

### 8.3 The mechanism — resolved

**`FAD-PERF-a` resolved 2026-07-27 ✅** in favour of **GCD**, which the brief asks for by name (`README.md` → *Tech requirements*). The reasoning, the cost, and the assumptions carried are in `non-functional-requirements.md §1.10`; `FAD-PERF-b` (§1.11) and `FAD-PERF-c` (§1.12) were ratified in the same commit.

The protocol boundary in §8.1 is what made this a contained decision rather than a structural one, and that was demonstrated rather than asserted: an `async/await` implementation was built first and then replaced with the GCD one. The change touched `ImageLoader.swift`, `RemoteImage.swift`, `MockImageLoader.swift` and the tests — and nothing else in the app. `RemoteImage` names `ImageLoading`, never `ImageLoader`.

### 8.4 Call-site consequence

`TweetView.avatar(_from:)` and `TweetView.fetchImage(_from:)` returned an image *synchronously* after starting an asynchronous load, so they could only ever return the placeholder (`fn-spec §4.4`). Views **MUST NOT** own image-loading state in a local variable.

`View/RemoteImage.swift` is the shape that replaced them: a small view holding its own `@State private var image: UIImage?` alongside the `@State private var token: ImageRequestToken?` it needs in order to cancel. Three lifecycle hooks, each load-bearing:

- `.onAppear` starts the load, guarded on `image == nil, token == nil` — in a lazy container it fires again every time the row scrolls back.
- `.onDisappear` cancels (`NFR-PERF-006`).
- `.onChange(of: urlString)` cancels, clears, and reloads. Without it a reused row keeps the previous tweet's image, because the `@State` survives the reuse. This is the view-identity trap §12 exists to point at.

`RemoteImage` applies `.resizable()` but never a `.frame`; sizing stays with the caller so no fixed width can leak in (`NFR-LAYOUT-001`).

SwiftUI's own `AsyncImage` was the obvious alternative and is rejected: it offers no cache control, no downsampling, and no coalescing, so `NFR-PERF-003/006/007` would all have gone unmet.

---

## 9. Configuration and Constants

- `Config/UrlConstant.swift` owns endpoint construction. The host is private; only the two typed builders are exposed. *`userProfleUrl(name:)` was renamed to `userProfileUrl(name:)` in commit 02, alongside its only caller.*
- `Config/Constant.swift` owns intrinsic sizes, font sizes, the fixed username, and the placeholder asset name. Constants describe things that are genuinely fixed regardless of device — an avatar is 40×40 everywhere. They **MUST NOT** be used to derive container widths (`NFR-LAYOUT-001`).
- ⛔ *Members are named in `SCREAMING_SNAKE_CASE` (`USER_NAME`, `FONT_SIZE_CONTENT`, `SENDER_AVATAR_SIZE`). Swift convention is `lowerCamelCase`. Rename as files are touched; do not do it as a standalone sweep (§2.3).*
- Duplicated constants are a smell: `HeaderView` re-declares its own `avatarImageWidth`/`nickNameFontSize` privately rather than reading `Constants`. Values used by exactly one view **MAY** stay local; values shared across views **MUST** live in `Config`.
- Page size (5) belongs here (§7.3).

---

## 10. Testing Architecture

### 10.1 The split

| Suite | Requires | Contents |
|-------|----------|----------|
| **Unit** | Nothing. Must pass with the network off (`NFR-TEST-002`). | Model decoding against `Tweets.json`; `HttpService` status validation against `Support/StubURLProtocol.swift`; `TweetService` / `UserService` against `MockBaseService`; `ImageLoader`'s cache, coalescing, downsampling and failure paths against the same `StubURLProtocol`; filtering rules; and `MomentsViewModel`'s initial window, loading flag and failure paths against `MockBaseService`, with the append and refresh transitions to follow those intents. |
| **Integration** | mountebank on `localhost:2727`. | `WeChatMomentsTests/Integration/HttpServiceIntegrationTests.swift` — the endpoints answer, the served feed is still 22 elements, and the catch-all really does return 404. |

*The split is expressed by folder and by class name, with each integration test opening `try XCTSkipUnless(Mountebank.isReachable)` — `FAD-TEST-a`, resolved in `nfr §4.8`. With mountebank stopped the whole suite passes and those tests report as skipped; no `-only-testing` selector is required to get a green offline run, though `-only-testing:WeChatMomentsTests/HttpServiceIntegrationTests` selects them when the mock is up.*

### 10.2 Fixtures

`WeChatMomentsTests/Resources/Tweets.json` is the canonical offline payload and mirrors what `imposters.ejs` serves, including all five malformed elements. *It is read by `WeChatMomentsTests/Models/TweetDecodingTests.swift` via `Bundle(for:).url(forResource:)`, satisfying `NFR-TEST-003`. Bundle membership is derived from the synchronized folder group (§2.5), not from an explicit `PBXResourcesBuildPhase` entry — confirmed working, and the reason `test_fixture_has_22_elements` exists as a guard.*

`WeChatMomentsTests/Config/TestDataConfig.swift` holds a second, inline set of JSON fixtures that overlaps with it. Two competing fixture sources is worse than either alone; its fate is `FAD-TEST-c`.

### 10.3 Mocks

- Live in `Mocks/` in the **app** target, wrapped in `#if DEBUG`, so previews and tests share them.
- One mock per protocol, named `Mock<Protocol-subject>` (`MockBaseService`, `MockImageLoader`).
- Record call counts and captured arguments; return values are configurable per instance.
- A mock **MUST NOT** contain production logic.

### 10.4 Template stubs

⛔ *`WeChatMomentsUITests/WeChatMomentsUITests.swift` is an unmodified Xcode template whose test bodies assert nothing. It inflates the test count without adding confidence and **SHOULD** be replaced with real tests or removed. Its unit-target counterpart, `WeChatMomentsTests/WeChatMomentsTests.swift`, was deleted in commit 02.*

---

## 11. Naming and File Organization Conventions

- **One type per file**, and the file is named for that type. *`Model/MyModels.swift` held four types under a name that described none of them; it was split into `Models/{Tweet,User,Comment,Img}.swift` in commit 01 alongside the expansion for `FR-API-003`.*
- **Role suffixes:** `…View`, `…ViewModel`, `…Service`, `…Loader`, `…Helper`. Protocols describing a capability are named for the capability (`BaseService`, `ImageLoading`).
- **Folders are plural** when they hold a collection of peers: `Models/`, `Services/`, `Extensions/`, `Mocks/`. ⛔ *`Extension/` is still singular. `Service/` was pluralised in commit 02, which edited every file in it; `Utils/` was removed entirely in commit 03 when its only occupant, `ImageHelper.swift`, was deleted.*
- **Singular/plural consistency within a feature.** ⛔ *`MomentView` (singular) pairs with `MomentsViewModel` (plural). The screen shows moments; both should be plural.*
- **Extensions** are named `Type+Purpose.swift`, not after the type alone. ⛔ *`Extension/Color.swift` should be `Color+Moments.swift`.*
- **Swift casing throughout.** `lowerCamelCase` for properties and constants (§9), `UpperCamelCase` for types.
- **Spelling is part of the API.** ⛔ *`commentsBackgroudColor` is still misspelled. `userProfleUrl` was corrected in commit 02, with its caller.*
- **Comments carry spec references.** Non-obvious code cites the requirement that motivates it — `// FR-PAGE-003: idempotent at end of list`, `// NFR-DATA-001: per-element tolerance`. This is how a reader (human or agent) gets from a line of code back to the reason it exists.

---

## 12. Development Tooling & Required Skills

- The **`swiftui-pro:swiftui-pro`** skill **MUST** be invoked before writing, modifying, or reviewing SwiftUI code in this project. It covers modern API usage, view-identity and state-ownership pitfalls (directly relevant to §4.1), and performance patterns for lazy containers (directly relevant to §7 and §8).
- No Figma or design-system skills apply — this project has no design source (`spec/README.md §5`).
- Where a skill's generic guidance conflicts with an approved decision in `spec/`, the project specifications win. See *Source-of-Truth Priority* in [`../CLAUDE.md`](../CLAUDE.md).

---

## 13. Open Decisions

Recorded rather than guessed. None of these blocks establishing the structure above.

1. **`FAD-ARCH-a` — pbxproj format.** **Resolved 2026-07-27 ✅** — see §2.5.
2. **`FAD-ARCH-b` — no shared Xcode scheme.** ⚠️ The only scheme lives in `WeChatMoments.xcodeproj/xcuserdata/`, so it is not in git and `xcodebuild -scheme WeChatMoments` works **only on the original author's machine**. Every build and test command in `CLAUDE.md` and in this spec depends on it. Moving it to `xcshareddata/xcschemes/` and committing it is a small change with outsized value for a reviewer cloning the repo, and it is a prerequisite for the test-plan option in `FAD-TEST-a`. *Deliberately deferred.*
3. **`FAD-ARCH-c` — withdrawn 2026-07-27.** This entry claimed the UI-test target's `PRODUCT_BUNDLE_IDENTIFIER` duplicated the unit-test bundle's. **It was wrong.** The identifiers are `com.gl.WeChatMomentsTests` and `com.gl.WeChatMomentsUITests` respectively and always were. The claim entered this document unverified; it is retained here as a withdrawal rather than deleted, per the deprecate-in-place rule in [`README.md §4`](./README.md).
4. **`FAD-ARCH-d` — composition root.** The target layout (§2.2) introduces `App/RootView.swift` to construct the view model and its services. Whether this is worth a file for a single screen, versus constructing in `WeChatMomentsApp`, is open. It becomes clearly worthwhile the moment §5.2's injection fix lands, because something has to supply the dependencies. *That moment arrived in commit 06 and the file was still declined, deliberately: the defaulted-argument initialisers mean nothing has to supply anything, so a `RootView` would today only forward. It is worth revisiting the first time a dependency must be chosen rather than defaulted — a preview or UI test wanting a stubbed feed is the likeliest trigger. The `Features/Moments/` migration (§2.2) was declined in the same commit for the same reason: bundled moves are cheap (§2.3), but this commit's diff is already a rewrite of the view model's lifetime, injection, loading and error handling.*
5. **`FAD-PERF-a` — concurrency mechanism** (§8.3). **Resolved 2026-07-27 ✅** — **GCD**, as the brief asks by name. Owned by `non-functional-requirements.md §1.10`, which records that an `async/await` implementation was built first and reverted, and what that cost. `FAD-PERF-b` and `FAD-PERF-c` were ratified alongside it (§1.11, §1.12).
6. **`FAD-DATA-b` — the `BaseService` failure type** (§5.2). **Resolved 2026-07-27 ✅** — `Services/NetworkError.swift`, carried end-to-end. Owned by `non-functional-requirements.md §2.12`; the protocol signature in §5.1 is updated accordingly.
7. **`FAD-TEST-a` — the unit/integration split** (§10.1). **Resolved 2026-07-27 ✅** — folder plus class-name convention plus an `XCTSkipUnless` reachability guard. Owned by `non-functional-requirements.md §4.8`. Note that it was resolved *without* resolving `FAD-ARCH-b`, which the test-plan alternative would have required.

---

## 14. Alignment with the Other Specifications

- Behavioural requirements come from [`functional-specification.md`](./functional-specification.md); this document says where they live, never what they are.
- Quality requirements come from [`non-functional-requirements.md`](./non-functional-requirements.md); §7, §8, and §10 exist to make `NFR-PERF-*`, `NFR-DATA-*`, and `NFR-TEST-*` achievable.
- Where this document marks a gap **⛔**, the authoritative requirement is the `FR-*` or `NFR-*` it cites. This document records the *structural* reason the gap exists.

---

*This document defines architecture and conventions only. It prescribes no visual detail and no product behaviour. No production code is affected by this document; the **⛔** markers describe the current state of the code, they do not change it.*
