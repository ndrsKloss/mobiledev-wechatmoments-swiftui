# Decision notes

One note per commit, explaining **what had to change and why** — including the alternatives that were considered and rejected. Each note is committed *with* the code it describes, so `git show <commit>` yields the change and its rationale together.

These notes answer "why is the code like this?". They are not requirements — requirements live in [`../../spec/`](../../spec/) and are referenced by ID.

## Index

| # | Note | README bullet | Commit |
|---|------|---------------|--------|
| 00 | [Synchronized folder groups](./00-synchronized-folder-groups.md) | *enabling — no bullet* | `chore(project): adopt synchronized folder groups…` |
| 01 | [Tweet model and lenient decoding](./01-tweet-model-and-lenient-decoding.md) | *enabling — no bullet* | `feat(model): decode sender, images and comments with per-element tolerance…` |
| 02 | Network hardening and injection | *enabling — no bullet* | pending |
| 03 | Async image loader with cache | *enabling — no bullet* | pending |
| 04 | Profile header | "The page consists of profile image, avatar and tweets list" | pending |
| 05 | Tweet cell | "For each tweet, there will be a sender, optional content, optional images and comments" | pending |
| 06 | Image grid | "A tweet contains from 0 to 9 images" | pending |
| 07 | Fetch and store, show first 5 | "All tweets are fetched and stored in memory at the first time…" | pending |
| 08 | Append 5 at the bottom | "Show 5 more while user pulling up the view at the bottom…" | pending |
| 09 | Pull to refresh | "Pulling down table view to refresh, only first 5 items are shown…" | pending |
| 10 | Adaptive layout | "Supports layout on all kinds of iOS device screen and orientation." | pending |
| 11 | Visual fidelity | "The project is an iPhone app which looks like Wechat Moments page." | pending |
| 12 | Static page | "This is a static page." | pending |

**Build order is not README order.** The pagination bullets are built 07 → 08 → 09 because refresh-resets-to-5 depends on both the window and the append existing first. Three notes cover enabling work that no single bullet owns but several depend on.

## Template

```markdown
# NN — <title>

**README bullet:** "<verbatim bullet, or 'enabling work — no bullet'>"
**Commit:** <conventional commit subject>
**Requirements:** FR-…, NFR-…

## What was wrong
## What changed
## Why this way
## Alternatives considered and rejected
## Requirements satisfied
## Verification
```
