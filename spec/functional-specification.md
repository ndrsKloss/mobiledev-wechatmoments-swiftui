# WeChat Moments — Functional Specification

> **Purpose:** define *what* the application does — screen anatomy, the data contract it consumes, and the observable behaviour of the feed, its pagination, and each tweet. This document defines **functional behaviour**, not implementation structure (see [`architecture-specification.md`](./architecture-specification.md)) and not quality attributes (see [`non-functional-requirements.md`](./non-functional-requirements.md)).
>
> **Source material:** the "Expected application behaviours" and "Tech requirements" sections of the root [`README.md`](../README.md), the three reference screenshots it embeds, and the payloads actually served by [`../imposters.ejs`](../imposters.ejs). Where these three disagree, §3 records what the mock server really returns — it is the contract the app must survive.
>
> **Normative language:** **MUST** = mandatory · **SHOULD** = strongly recommended · **MAY** = optional.
>
> **Confidence tags:** `[C]` confirmed — stated in the brief or observed in the served payload · `[I]` inferred from the reference screenshots · `[A]` assumption requiring confirmation.
>
> **⛔** marks a requirement the current code does not satisfy.

---

## 1. Product Overview

A single-screen iPhone app reproducing the **WeChat Moments** page: a large profile header followed by a vertically scrolling feed of tweets.

The screen is **static** in the product sense — the brief states *"This is a static page."* The user can scroll, pull to refresh, and load more. There is no compose action, no like, no comment entry, no navigation to a second screen, and no authentication. The displayed user is fixed (`jsmith`, `Constants.USER_NAME`).

The whole product is therefore: **fetch two endpoints, render a header and a paginated list, and do not fall over on bad data.**

---

## 2. Screen Anatomy

| # | Region | Contents | Rendered today by | Status |
|---|--------|----------|-------------------|--------|
| 1 | **Profile header** | Full-bleed profile (cover) image; the user's nick and avatar overlaid near its bottom edge. | `View/HeaderView.swift` | Present; profile image never loads (§3.1) |
| 2 | **Tweet cell** | Sender avatar (leading), sender nick, optional text content, optional image grid, optional comment block. | `View/TweetView.swift` | Placeholders only — sender nick is the literal string `"Placeholder Profile"`, avatar receives `nil`, grid receives `[]` |
| 3 | **Comment block** | Zero or more comment rows, each *"<sender nick>: <content>"*. Hidden entirely when there are no comments. | `View/CommentRowView.swift` | Exists, **not wired in** |
| 4 | **Cell separator** | A hairline rule between tweets. | `View/FooterView.swift` | Exists, **not wired in**; `MomentView` uses a plain `Divider()` instead |
| 5 | **Loading indicator** | A circular progress indicator while the initial fetch is in flight. | `MomentView.swift` (`.overlay`) | Present; toggle logic is unbalanced (`arch-spec §4.2`) |

The header scrolls with the feed — it is the first row of the list, not a pinned chrome element. `[C]` (`MomentView` places `HeaderView` inside the `List`.)

**Layout values.** The concrete dimensions currently in `Config/Constant.swift` (avatar 40×40, profile 75×75, grid cell 82×82, content font 15pt, comment font 12pt) are `[I]` — derived from the reference screenshots by the original author, not specified anywhere. They are treated as the accepted baseline and MAY be adjusted for `NFR-LAYOUT` compliance without being a spec change.

---

## 3. Data Contract (`FR-API`)

The app consumes a **mountebank** mock served from `http://localhost:2727` (`Config/UrlConstant.swift`). Two stubs plus a catch-all.

### 3.1 `GET /user/{username}` — the profile

Served payload:

```json
{
  "profile-image": "https://techops-recsys-lateral-hiring.github.io/moments-data/images/user/profile-image.jpeg",
  "avatar":        "https://techops-recsys-lateral-hiring.github.io/moments-data/images/user/avatar.png",
  "nick":          "Huan Huan",
  "username":      "hengzeng"
}
```

**The profile-image key is hyphenated.** The payload key is `profile-image` and the Swift property is `User.profile`, so the mapping must be declared explicitly. `Models/User.swift` does so (`case profile = "profile-image"`). *Until commit 01 there were no `CodingKeys` at all, so `profile` always decoded to `nil` and the cover image could never appear — the cover image will not actually render until the image loader lands (`NFR-PERF-002`).*

| ID | Level | Requirement |
|----|-------|-------------|
| `FR-API-001` | MUST | The user model **MUST** map the payload key `profile-image` onto its profile-image property via `CodingKeys`. |
| `FR-API-002` | MUST | All four user fields (`username`, `nick`, `avatar`, `profile-image`) **MUST** be treated as optional; a missing field renders a fallback (`NFR-DATA-004`), never a crash. |

### 3.2 `GET /user/{username}/tweets` — the feed

Served payload: a JSON **array of 22 elements**. The well-formed element shape is:

```json
{
  "content": "…",
  "sender":  { "username": "…", "nick": "…", "avatar": "…" },
  "images":  [ { "url": "…" } ],
  "comments":[ { "content": "…", "sender": { "username": "…", "nick": "…", "avatar": "…" } } ]
}
```

`content`, `images`, and `comments` are each independently optional. `sender` is present on every well-formed element.

### 3.3 The feed is deliberately hostile `[C]`

The 22 elements break down as follows — this is the exact composition served today, and every one of these cases is intentional:

| Count | Element shape | What it exercises |
|-------|---------------|-------------------|
| 5 | `sender` + `content` | Text-only tweet |
| 4 | `sender` + `content` + `images` + `comments` | The full case |
| 4 | `sender` + `images` | **Image-only tweet, no content** |
| 1 | `sender` + `content` + `images` | No comments |
| 1 | `sender` + `content` + `comments` | No images |
| 2 | `sender` only | Empty tweet — nothing to display |
| 4 | `{"error": "losted" \| "illegal" \| "WHY" \| "WOW"}` | **Malformed element** |
| 1 | `{"unknown error": "STARCRAFT2"}` | **Malformed element, different key** |

Two entries carry `"comments": []` — an *empty* comment array, distinct from an absent one. Image counts across the array are `0…9`, with one element carrying the maximum of **9**.

**Displayable tweets = 15.** (17 elements have a `sender`; 2 of those have neither content nor images and are dropped by `FR-DATA-001`.) At 5 per page that is 3 full pages plus a partial — enough to exercise `FR-PAGE-*` end-to-end.

**The whole-array decode trap.** `JSONDecoder` fails a container **atomically**: one malformed element aborts the entire array. Because `Tweet.sender` is non-optional, the five malformed elements throw, so decoding the feed as `[Tweet]` fails outright and would leave the app entirely blank. `TweetService` therefore decodes `[FailableDecodable<Tweet>]` and compact-maps the result (`NFR-DATA-001`), which costs one tweet per malformed element instead of the whole feed.

This coupling is load-bearing and easy to undo by accident: relaxing `sender` back to optional would make the tolerance decorative, and dropping the tolerance would blank the feed. `TweetDecodingTests.test_strict_decoding_of_the_whole_array_fails` pins the first half of that invariant.

| ID | Level | Requirement |
|----|-------|-------------|
| `FR-API-003` | MUST | The tweet model **MUST** decode `sender`, `content`, `images`, and `comments`. |
| `FR-API-004` | MUST | A malformed element in the feed array **MUST NOT** fail the decode of the remaining elements. See `NFR-DATA-001` for the mechanism. |
| `FR-API-005` | MUST | A non-2xx HTTP response **MUST** be surfaced as an error, not passed to the decoder. *`HttpService.get(url:)` validates the status before returning the body and fails with `NetworkError.httpStatus(_:)`. See `NFR-DATA-003`.* |
| `FR-API-006` | MUST | Image and avatar URLs point at a **real remote host** (`techops-recsys-lateral-hiring.github.io`); the mock serves JSON only. Image loading is therefore genuinely networked and **MUST** obey `NFR-PERF-*`. |

### 3.4 Catch-all stub

Any unmatched path returns **404** with `{"error": "User not found"}`. The existing `test_wrong_url` tests depend on this.

---

## 4. Functional Requirements

### 4.1 Profile header (`FR-HEADER`)

| ID | Level | Requirement |
|----|-------|-------------|
| `FR-HEADER-001` | MUST | The header **MUST** display the user's profile image as a full-bleed banner, the user's avatar, and the user's nick. ⛔ *Partially met — profile image blocked by `FR-API-001`; avatar blocked by `NFR-PERF-002` (see below).* |
| `FR-HEADER-002` | MUST | Each of the three elements **MUST** render a placeholder when its source is missing or fails to load — never an empty gap and never a crash. ⛔ *Not met — `HeaderView.setProfileImage(for:)` force-unwraps `image!` inside the load callback.* |
| `FR-HEADER-003` | SHOULD | The header **SHOULD** scroll with the feed rather than pin to the top. |

Note on the avatar: `HeaderView.setAvatarImage(for:)` calls the **synchronous** `ImageHelper.getImage(_:forSize:)` overload, which unconditionally `return nil`. The avatar therefore never loads either. Fixing this is `NFR-PERF-002`.

### 4.2 Feed loading (`FR-FEED`)

| ID | Level | Requirement |
|----|-------|-------------|
| `FR-FEED-001` | MUST | On first appearance the app **MUST** fetch the profile and the full tweet list, and **MUST** hold the complete tweet list in memory. *(Brief: "All tweets are fetched and stored in memory at the first time".)* |
| `FR-FEED-002` | MUST | The in-memory list **MUST** be the sole source for pagination — scrolling and refreshing **MUST NOT** re-request the feed endpoint. Pull-to-refresh is the one exception (`FR-PAGE-004`). |
| `FR-FEED-003` | MUST | A loading indicator **MUST** be shown while the initial fetch is in flight and hidden when it settles, in both the success and failure cases. ⛔ *Not met — `MomentsViewModel.loadData()` toggles `showIndicator` twice synchronously before either request completes, then each completion toggles it again; the flag does not track the actual in-flight state.* |
| `FR-FEED-004` | MUST | Total failure of the feed request **MUST** produce a user-visible error state, not a silently empty list. ⛔ *Not met — errors are `print`ed only.* |
| `FR-FEED-005` | SHOULD | Failure of the profile request **SHOULD NOT** prevent the feed from rendering, and vice versa. The two requests are independent. |

### 4.3 Pagination (`FR-PAGE`)

The brief's three pagination sentences, made precise. **Page size is 5.**

| ID | Level | Requirement |
|----|-------|-------------|
| `FR-PAGE-001` | MUST | After the initial load, exactly the **first 5** displayable tweets **MUST** be shown. ⛔ *Not met — no pagination exists; `MomentView` renders every tweet the view model holds.* |
| `FR-PAGE-002` | MUST | When the user scrolls to the bottom of the list, the next **5** tweets **MUST** be appended to the displayed window. ⛔ *Not met.* |
| `FR-PAGE-003` | MUST | Appending **MUST** stop cleanly once the in-memory list is exhausted; the final page **MAY** contain fewer than 5 tweets. Reaching the end **MUST NOT** trigger a repeated append or an error. |
| `FR-PAGE-004` | MUST | Pull-to-refresh **MUST** reset the displayed window to the **first 5** tweets. *(Brief: "only first 5 items are shown after refreshing".)* ⛔ *Not met — no refresh control exists.* |
| `FR-PAGE-005` | MUST | The displayed window is derived state owned by the view model, not by the view. See `arch-spec §7`. |
| `FR-PAGE-006` | SHOULD | Whether pull-to-refresh **re-fetches** the feed from the network or merely resets the window over the cached list is open — see §8 Q2. Until resolved, re-fetching is the safer reading of "refresh". |

### 4.4 Tweet rendering (`FR-TWEET`)

| ID | Level | Requirement |
|----|-------|-------------|
| `FR-TWEET-001` | MUST | Every displayed tweet **MUST** show its sender's nick and avatar. ⛔ *Not met — `TweetView` hard-codes `Text("Placeholder Profile")` and calls `avatar(_from: nil)`.* |
| `FR-TWEET-002` | MUST | Text content is **optional**. When absent, no empty text row is rendered. ⛔ *Not met — `TweetView` renders `Text(tweet.content ?? "")` unconditionally.* |
| `FR-TWEET-003` | MUST | Content text **MUST** wrap to as many lines as it needs; it **MUST NOT** be truncated. |
| `FR-TWEET-004` | MUST | Images are **optional**, and when present number **1 to 9**. The grid **MUST** render exactly as many cells as there are images — no placeholder padding cells. ⛔ *Not met — `TweetView.addImagesToView(_from:)` renders a fixed `0..<imageLimit` (5) range, padding short sets with the empty-image asset and truncating sets larger than 5.* |
| `FR-TWEET-005` | MUST | The image grid layout **MUST** follow §5. |
| `FR-TWEET-006` | MUST | Comments are **optional**. An absent *or empty* `comments` array **MUST** render no comment block at all — no header, no spacing. |
| `FR-TWEET-007` | MUST | Each comment row **MUST** show the commenter's nick followed by the comment text, visually distinguished (the nick tinted, per the reference screenshots `[I]`). The comment block sits on its own background fill (`Extension/Color.swift`). |
| `FR-TWEET-008` | SHOULD | A tweet cell **SHOULD** be visually separated from the next by a hairline rule. `View/FooterView.swift` exists for this purpose and **SHOULD** be used in place of the ad-hoc `Divider()` currently in `MomentView`. |

⚠️ **A structural note on `TweetView`'s image helpers.** `avatar(_from:)` and `fetchImage(_from:)` both call the *asynchronous* closure overload of `ImageHelper.getImage` and then immediately `return` a local variable the callback has not yet written. They can only ever return the placeholder / `nil`. Separately, `addImagesToView(_from:)` ends in `.padding() as? AnyView`, a cast that always yields `nil` because `padding()` returns a `ModifiedContent`, not an `AnyView`. Both helpers are structurally incapable of working and must be rewritten, not patched — see `arch-spec §8`.

### 4.5 Data filtering (`FR-DATA`)

| ID | Level | Requirement |
|----|-------|-------------|
| `FR-DATA-001` | MUST | A tweet with **neither** content **nor** images **MUST NOT** be displayed. (2 elements in the served feed are `sender`-only.) |
| `FR-DATA-002` | MUST | A tweet with images but **no** content **MUST** be displayed. ⛔ *Not met — `MomentsViewModel.loadTweets()` filters on `$0.content != nil`, which discards all 4 image-only tweets. `FR-DATA-001` is the correct, narrower rule; the current filter is a proxy for it that removes legitimate content.* |
| `FR-DATA-003` | MUST | Malformed elements (§3.3) **MUST** be dropped silently and **MUST NOT** be counted toward a page. |
| `FR-DATA-004` | SHOULD | Filtering **SHOULD** happen once, at the boundary where the feed enters memory, so that pagination indices refer only to displayable tweets. |

---

## 5. Image Grid Rules

Derived from the reference screenshots `[I]`; the brief states only the 0–9 range `[C]`.

| Image count | Columns | Cell sizing |
|-------------|---------|-------------|
| 0 | — | No grid rendered. |
| 1 | 1 | Single image, larger than a grid cell, aspect-ratio preserved `[A]`. |
| 2–3 | 3 | One row, cells left-aligned; the row is **not** stretched to fill the width. |
| 4 | 2 | 2×2 block `[A]` — the classic WeChat special case. |
| 5–6 | 3 | Two rows, last row partially filled and left-aligned. |
| 7–9 | 3 | Three rows. 9 images fills a complete 3×3. |

| ID | Level | Requirement |
|----|-------|-------------|
| `FR-TWEET-009` | MUST | Grid cells **MUST** be square and uniformly sized within a tweet, and images **MUST** fill them without distortion (aspect-fill + clip). |
| `FR-TWEET-010` | MUST | The grid **MUST NOT** use a hard-coded pixel width for the row; cell size derives from the available width so the layout survives `NFR-LAYOUT-001`. |
| `FR-TWEET-011` | SHOULD | The 1-image and 4-image special cases **SHOULD** be implemented as described. Both are tagged `[A]` — see §8 Q3. |

---

## 6. Out of Scope

Explicitly **not** requirements, per the brief's *"This is a static page."*:

- Composing a tweet, posting, deleting.
- Liking, commenting, or any write operation.
- Navigation to any second screen; there is no navigation stack.
- Authentication, account switching, or any user other than `jsmith`.
- Persistence across launches. The in-memory list of `FR-FEED-001` lives for the lifetime of the process only.
- Tapping an image to open a full-screen viewer.
- Localization, dark mode, and VoiceOver — see `spec/README.md §5` for why these are deliberately excluded.

---

## 7. Acceptance Criteria

With mountebank running (`mb --configfile imposters.ejs`):

- **Header** — the cover image, avatar, and nick "Huan Huan" all render. No placeholder remains visible once the network settles. (`FR-HEADER-001/002`)
- **Initial page** — exactly 5 tweets are visible on first load. (`FR-PAGE-001`)
- **Append** — scrolling to the bottom three times yields 10, then 15, then no further growth and no error. (`FR-PAGE-002/003`)
- **Refresh** — pulling down returns the list to 5 tweets. (`FR-PAGE-004`)
- **Content variety** — across the 15 displayable tweets, all of these are visible: a text-only tweet, an **image-only tweet with no text**, a tweet with 9 images in a 3×3 grid, a tweet with comments, and a tweet whose `comments` array is empty rendering **no** comment block. (`FR-TWEET-002/004/006`, `FR-DATA-002`)
- **Hostile data** — none of the 5 malformed elements appears as a blank or broken cell, and their presence does not blank the feed. (`FR-API-004`, `FR-DATA-003`)
- **Empty tweets** — the 2 `sender`-only elements do not appear. (`FR-DATA-001`)
- **Offline** — with mountebank stopped, the app shows an error state rather than an indefinitely spinning indicator or a silent blank screen. (`FR-FEED-003/004`)

---

## 8. Open Questions

Referenceable as `fn-spec §8 Q<n>`.

1. **Scroll trigger point.** Does "pulling up the view at the bottom" mean the last cell becoming visible, or the user over-scrolling past the end? The former is the conventional infinite-scroll reading and is assumed `[A]`; it changes the feel materially.
2. **Refresh semantics.** ⚠️ Does pull-to-refresh re-request `/tweets`, or only reset the displayed window over the already-cached list? The brief says both "all tweets are fetched... at the first time" and "only first 5 items are shown after refreshing" — compatible with either. See `FR-PAGE-006`.
3. **Grid special cases.** ⚠️ Are the 1-image and 4-image layouts (§5) actually special-cased, or does every count use a uniform 3-column grid? The reference screenshots do not contain a 1- or 4-image tweet.
4. **Page-append indicator.** Is a spinner shown while the next 5 are appended? Since the data is already in memory the append is instantaneous, so probably not `[A]` — but this changes if Q2 resolves toward re-fetching.
5. **Malformed-element accounting.** `FR-DATA-003` drops them silently. Should the count of dropped elements be logged for diagnostics?
6. **Fewer than 5 displayable tweets.** Not reachable with the current fixture (15 available), but the behaviour should be defined for robustness: render what exists, no padding, no empty-state message.
7. **Comment block ordering and truncation.** Are comments capped at some count with a "view more" affordance, or always shown in full? Full display is assumed `[A]`.

---

*This document defines functional behaviour only. It prescribes no types, no frameworks, and no file layout — those belong to [`architecture-specification.md`](./architecture-specification.md). No production code is affected by this document.*
