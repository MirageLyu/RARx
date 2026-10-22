# Architecture

This document describes how RARx turns a Finder open event into a safe,
non-destructive extraction. It is intended for contributors who need to modify
the extraction pipeline or review its security properties.

## Design goals

RARx is built around four constraints:

1. **Finder-first behavior.** A normal double-click must complete without a main
   window, destination picker, or confirmation step.
2. **Non-destructive results.** Existing files are never overwritten by the
   extraction merge.
3. **Untrusted archive input.** Archive paths, links, and filenames are treated
   as hostile until validated.
4. **Testable core logic.** Extraction and filesystem behavior live outside the
   SwiftUI/AppKit layer.

## Process model

RARx is a background LaunchServices application:

- `LSUIElement` is `true`, so the app starts without a Dock icon or menu bar
  presence.
- `LSMultipleInstancesProhibited` is `true`, so LaunchServices reuses a running
  instance for subsequent open events.
- The app receives files through `NSApplicationDelegate.application(_:open:)`
  and the legacy `application(_:openFiles:)` callback.
- If an open event arrives before the extraction controller is initialized, the
  URLs are buffered and delivered after launch.
- A Finder-driven launch does not intentionally present the Settings window.
  Password and error alerts are shown as floating panels. Settings is opened only
  when the app is launched directly.
- After the queue is empty, the app terminates. If the Settings window is open,
  it stays alive so the user can change settings.

## Main components

| Component | Responsibility |
| --- | --- |
| `AppDelegate` | Launch lifecycle, Finder events, menu, settings window, idle termination. |
| `AutoExtractionController` | Serial queue, password retries, user prompts, error presentation, cancellation. |
| `VolumeResolver` | Maps a later `name.partN.rar` volume to `name.part1.rar`. |
| `UnrarEngine` | Runs `unrar` with controlled arguments and parses archive metadata. |
| `ProcessRunner` | Executes child processes, drains output, supports cancellation, and sends signals. |
| `SafeExtractionService` | Resource checks, staging, validation, commit orchestration, and cleanup. |
| `FileMerger` | Non-overwriting directory merge with a move journal and rollback. |
| `ExtractionProgressMonitor` | Measures extraction progress from staged file sizes. |
| `ExtractionHUDController` | Optional non-activating progress panel. |
| `DefaultHandlerManager` | LaunchServices registration and verification. |

## Open event flow

1. LaunchServices delivers one or more file URLs to `AppDelegate`.
2. `AutoExtractionController.enqueue(_:)` filters unreadable or non-`.rar`
   inputs and removes duplicates that are already queued or active.
3. The controller processes one archive at a time.
4. `VolumeResolver` checks whether the opened file is a later volume and selects
   the first volume when possible.
5. `UnrarEngine.inspect(archive:password:)` runs `unrar lt` to determine archive
   format, encryption state, file count, and total uncompressed size.
6. If the archive has encrypted headers and no password is available, the
   controller asks for a password and retries inspection.
7. If the archive has encrypted file data with clear headers, inspection
   succeeds and the password is requested before extraction.
8. `SafeExtractionService` performs the extraction transaction described below.
9. The controller reports warnings, optional sound, and errors. The next queued
   archive is then processed.

## Extraction transaction

`SafeExtractionService.extract` is deliberately split into phases:

1. **Preflight.** Confirm the destination directory exists. Compare the
   archive's uncompressed size against available volume capacity, with a margin.
2. **Stale cleanup.** Remove abandoned hidden staging directories whose PID lock
   belongs to a dead process. Recent lockless directories are preserved.
3. **Staging.** Create `.rarx-<uuid>.tmp` inside the destination and a sibling
   `.rarx-<uuid>.lock` containing the owning process ID. Both are hidden from
   normal Finder presentation.
4. **Extraction.** Run UnRAR with `x -y -o+ -c- -cfg- -ts` into the staging
   directory. With a password, UnRAR is started with `-p` and the password is
   supplied on stdin. Without a password, `-p-` disables prompting.
5. **Write confinement.** When available, the UnRAR process is launched through
   `/usr/bin/sandbox-exec` with a profile that denies all file writes except the
   staging directory and standard device files. This is not a full App Sandbox.
6. **Validation.** Walk the staged tree. Symlinks resolving outside the staging
   directory are removed. Regular files with multiple hard links are removed.
   Warnings are preserved and shown to the user after the merge.
7. **Commit.** `FileMerger` recursively merges staged content into the
   destination. Existing files are never replaced. Conflicts get suffixes such
   as ` 2` and ` 3`. Every move is recorded for rollback.
8. **Cleanup.** Remove the staging directory and lock. If the commit fails and
   rollback cannot complete, the staging directory is preserved and its path is
   included in the error.

The merge is not a single filesystem transaction. A process crash during the
merge can leave some files in the destination and some in staging. On the next
extraction, the dead PID lock identifies the staging directory as abandoned and
removes the remaining staged data.

## Password handling

- Passwords are never passed as command-line arguments.
- UnRAR is launched with `-p`; the password is written to the child's stdin and
  the pipe is closed.
- Passwords are cached in memory only for the current queue and are cleared when
  the queue becomes empty.
- Passwords are not written to logs, UserDefaults, or the network.
- A wrong password during inspection causes another prompt. A wrong password
  during extraction causes the staging result to be discarded, then another
  prompt. The controller stops after three failed attempts.

## Progress reporting

UnRAR buffers terminal progress output when stdout is a pipe. RARx therefore
derives progress from the logical file sizes visible under the staging
directory, polling approximately every 350 ms. This works for a single large
file and for many small files.

The optional HUD shows the current file and percentage. The panel is
non-activating, joins all Spaces, and can be dismissed by cancellation. The HUD
is disabled by default; Finder-driven extraction remains completely silent
unless the user enables it.

## Failure handling

- A zero exit status is treated as success.
- Exit status `1` is treated as a warning. It is committed only when the output
  does not contain known fatal markers such as missing volumes, CRC failures, or
  permission errors.
- Exit status `11` is treated as an incorrect or missing password.
- Other non-zero statuses are fatal. The staging directory is removed without
  merging.
- Cancellation terminates the child process (SIGTERM, followed by SIGKILL if
  necessary), removes staging, and exits without an error dialog.
- Fatal extraction errors are presented in a floating alert with a button to
  open the log directory.

## Security boundaries

- RARx is not App Sandboxed. The app itself needs filesystem access to read the
  archive and merge staged files.
- The write confinement applies only to the UnRAR child process. `sandbox-exec`
  is deprecated and should be treated as defense in depth, not a security
  boundary on its own.
- The staging directory is created inside the destination to keep the commit on
  one volume and avoid cross-volume copies.
- `FileMerger` uses `lstat` rather than following symbolic links when checking
  destination conflicts. A destination symlink is treated as a conflict and is
  never followed.
- The application avoids shell invocation entirely. All child processes use
  argument arrays.
- Logs are useful for diagnostics and contain archive paths and UnRAR messages.
  They never contain passwords.

## Testing

- `Tests/CoreTests.swift` exercises the engine and transaction logic without
  AppKit, including malformed archives, password failures, conflicts, volume
  resolution, link validation, and stale staging cleanup.
- `scripts/test.sh` compiles and runs the core suite, then launches the real
  application through `open` to verify Finder-style behavior and LaunchServices
  registration.
- The localization check verifies that every `L(...)` key used in the source
  exists in both `en.lproj` and `zh-Hans.lproj`, and that format specifiers match.
- The GUI integration tests require a logged-in macOS session.
- Archive fixtures are small and checked into the repository. They contain no
  user data.

## Constraints and non-goals

- RAR creation is out of scope. UnRAR's license prohibits using its source to
  build a RAR-compatible archiver.
- Replacing files is intentionally not supported; the merge is always
  non-destructive.
- The app does not provide archive browsing or selective extraction.
- The application UI follows the macOS preferred language and is localized for
  English and Simplified Chinese. Documentation and command-line tooling are in
  English.
- Distribution as a notarized build is out of scope for the repository. The
  build script produces an ad-hoc signed local build.
