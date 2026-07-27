# 00 — Synchronized folder groups

**README bullet:** *enabling work — no bullet.*
**Commit:** `chore(project): adopt synchronized folder groups so file moves stop touching pbxproj (FAD-ARCH-a)`
**Requirements:** `FAD-ARCH-a`

## What was wrong

`WeChatMoments.xcodeproj/project.pbxproj` used the old explicit-file-listing format — `objectVersion = 56`, no `PBXFileSystemSynchronizedRootGroup` anywhere. In that format the project file maintains its own parallel copy of the directory tree: every source file needs a `PBXFileReference` (its path), an entry in a `PBXGroup.children` array (its folder), and a `PBXBuildFile` plus a line in the target's `PBXSourcesBuildPhase` (its target membership).

Adding one file therefore means three coordinated edits to a file that nothing but Xcode validates, and a mistake produces a project that fails to open rather than a clear error.

The implementation sequence that follows this commit adds roughly **fifteen** new files — models split one-per-type, a failable-decoding wrapper, an image loader, a remote-image view, two mocks, and several test files. That is about 45 hand edits spread across twelve commits.

## What changed

Migrated to `objectVersion = 77` with one `PBXFileSystemSynchronizedRootGroup` per target (`WeChatMoments`, `WeChatMomentsTests`, `WeChatMomentsUITests`). Each root group is wired to its target through a new `fileSystemSynchronizedGroups` entry.

Everything the filesystem already expresses was deleted from the project file: all 26 `PBXBuildFile` entries, all 24 non-product `PBXFileReference` entries, all 14 nested `PBXGroup`s, and the contents of every `Sources` and `Resources` build phase. Only the root group, the `Products` group, and the three built-product references remain.

`project.pbxproj` went from **33.1 KB to 20.0 KB**. Every byte removed was bookkeeping duplicating the directory layout.

## Why this way

The alternative was to keep paying the three-edit tax, and the arithmetic is what settled it: one contained risk that a single build verifies immediately, versus 45 diffuse ones each capable of silently dropping a file from compilation. A dropped file does not fail loudly — it fails as "undefined symbol" somewhere unrelated, or worse, as a stale implementation that still compiles.

It also removes an entire class of merge conflict. `project.pbxproj` is the classic unmergeable file in an Xcode repo; with synchronized groups it stops changing at all during ordinary work.

The prerequisite was Xcode 16+. This machine runs **Xcode 26.2**, so the constraint that made this a deferred decision when `spec/architecture-specification.md` was written no longer applied.

## Alternatives considered and rejected

**Stay on `objectVersion = 56` and hand-edit per file.** Rejected on the risk arithmetic above. It was the plan of record until the Xcode version was actually checked rather than assumed.

**Do the migration in Xcode's UI instead of by transform.** Xcode offers this conversion, and it would have been the safer route in principle. Rejected because it cannot be driven from here, and because the transform is verifiable: a clean build that compiles the same file list is stronger evidence than "Xcode said OK".

**Migrate lazily, one folder at a time.** Not possible — `objectVersion` is a project-wide property. The migration is all-or-nothing by construction.

## Requirements satisfied

- **`FAD-ARCH-a` ratified ✅** — recorded in `spec/architecture-specification.md §2.5` with the rationale and the assumption carried (every file under a target's directory belongs to that target; an exclusion would need a `PBXFileSystemSynchronizedBuildFileExceptionSet`).
- `spec/architecture-specification.md §2.3` (migration rule) rewritten: moves are now a filesystem operation and `project.pbxproj` should no longer appear in any diff.
- `CLAUDE.md` → *Repository Structure* note updated to match.

## A correction this commit forced

While applying the change I found that **`FAD-ARCH-c` was factually wrong**. It claimed the UI-test target's `PRODUCT_BUNDLE_IDENTIFIER` duplicated the unit-test bundle's. It does not, and never did — the two targets carry `com.gl.WeChatMomentsTests` and `com.gl.WeChatMomentsUITests` respectively.

That claim reached the specification without being checked against the project file. It has been **withdrawn in place** rather than deleted, per the deprecate-don't-delete rule in `spec/README.md §4`, so the error stays visible in the record.

## Verification

- Clean build from an emptied DerivedData: **BUILD SUCCEEDED**, compiling all 17 source files — verified by diffing the compiled-file list against `find WeChatMoments -name '*.swift'`. Nothing was silently dropped.
- Full test run against the live mock: results **identical to the pre-migration baseline** — the same two pre-existing failures (`TweetServiceTests.test_wrong_url`, `UserServiceTests.test_right_url`), the same passes, no new failures. The migration is behaviour-neutral, which is exactly what a pure project-format change should be.
- Both test targets pick up their sources, and the UI-test runner launches under its own bundle identifier.
