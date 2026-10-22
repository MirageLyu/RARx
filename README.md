# RARx

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: macOS 13+](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey.svg)](#requirements)

RARx is an unofficial, native macOS RAR extractor built around a Finder-first
workflow. Double-click a `.rar` archive in Finder and RARx extracts it into the
directory containing the archive, without opening a main window or asking where
to put the files.

RARx runs as a background LaunchServices application (`LSUIElement`). It opens a
floating password prompt only for encrypted archives. The app surfaces only the
prompts, failures, and warnings that require user attention. When launched by
Finder, the process exits after the queue is empty.

> RARx is not affiliated with RARLAB. RAR is a trademark of RARLAB.

## Project status

- Version 1.1.0.
- Tested on macOS 26.6.2 on Apple Silicon.
- Universal application and engine (`arm64` and `x86_64`).
- Documentation and command-line output are in English. The application UI
  follows the macOS preferred language and is localized for English and
  Simplified Chinese.

## Documentation

- [Architecture](ARCHITECTURE.md)
- [Security policy](SECURITY.md)
- [Contributing](CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)

## Features

- **Finder-first extraction.** Opening one or more `.rar` files starts a
  background queue. Each archive is extracted beside its own `.rar` file.
- **No main window.** By default, normal extraction does not show a window,
  dialog, or confirmation. The Finder-launched process exits when processing is
  complete.
- **Encrypted archives.** Password-protected headers and file data are
  supported. A password prompt appears only when a password is required.
- **Multi-volume archives.** Opening `name.part2.rar` uses `name.part1.rar` as
  the starting volume. Missing volumes are reported as errors.
- **Non-destructive conflicts.** Existing files are never overwritten.
  Conflicting incoming files are renamed with Finder-style suffixes
  (`name 2.ext`, `name 3.ext`). Directories are merged.
- **Safe staging.** Extraction happens in a hidden staging directory inside the
  destination. Fatal errors before the commit phase and cancellation leave the
  destination unchanged.
- **Optional progress window.** A compact, non-activating progress panel can be
  enabled in Settings. When extraction lasts longer than one second, the panel
  appears and offers cancellation. It is disabled by default.
- **Diagnostics.** Failures and warnings are logged with enough context to
  investigate the extraction. Passwords are never logged.
- **Localized interface.** The app follows the system language and includes
  English and Simplified Chinese translations. Unsupported languages fall back
  to English.

## Requirements

- macOS 13 or later.
- To build: the Swift toolchain included with the Xcode Command Line Tools or
  Xcode, plus the standard macOS command-line tools used by the build scripts.
- To install into `/Applications`: write access to `/Applications` for the
  current user.

The UnRAR source is vendored in [`vendor/unrar`](vendor/unrar), so building does
not require network access.

## Install

```bash
git clone https://github.com/MirageLyu/RARx.git
cd RARx
./scripts/install.sh
```

The installer performs these steps:

1. Uses an existing build, or builds the app if `build/RARx.app` is missing.
2. Stops any running RARx process.
3. Installs the bundle at `/Applications/RARx.app`.
4. Refreshes LaunchServices and unregisters the development copy.
5. Sets RARx as the default handler for `com.rarlab.rar-archive` for the current
   user, then verifies the registration.

Installing changes the current user's default `.rar` handler. Review
[`scripts/install.sh`](scripts/install.sh) before running it if you prefer to
perform these steps manually.

## Build

```bash
./scripts/build-engine.sh   # Optional; build-app.sh invokes it when needed.
./scripts/build-app.sh
```

Artifacts:

- `build/RARx.app`: the assembled, ad-hoc signed application.
- `build/engine/unrar`: the universal UnRAR executable.
- `build/icons/`: generated application and document icons.

The app is built with the hardened runtime and an ad-hoc signature. It is not
notarized. macOS may block the app when it is downloaded from the internet or
copied to another Mac. Use a Developer ID certificate and notarization for
distribution outside your own machine.

## Tests

```bash
./scripts/test.sh
# Also test the installed copy and its LaunchServices association:
APP=/Applications/RARx.app ./scripts/test.sh
```

The suite has three parts:

- A localization check that verifies the English and Simplified Chinese keys
  match the strings used in the source and preserve format specifiers.
- A headless core test binary covering archive inspection, extraction,
  passwords, multi-volume handling, conflict resolution, path validation, and
  staging cleanup.
- Finder-level integration tests that exercise the real application through
  `open` and LaunchServices. These tests require an active, logged-in macOS GUI
  session.

The RAR fixtures are checked in under [`Tests/Fixtures`](Tests/Fixtures). They
contain no user data.

## Usage

### Finder

1. Double-click a `.rar` file.
2. RARx extracts it into the directory containing the archive.
3. If the archive is encrypted, enter the password in the floating prompt.
4. The process exits when the queue is empty.

No destination picker is shown. To extract to a different location, move the
archive to that directory before opening it.

### Settings

Launch RARx from `/Applications` to open Settings. The settings window can:

- Confirm or change the default `.rar` handler.
- Enable or disable the optional progress panel.
- Enable or disable the completion sound.
- Open the log directory or the license notices.

## Security

RARx treats archive contents as untrusted input. The main safeguards are:

- Extraction runs in a hidden staging directory under the destination.
- On current macOS versions, the UnRAR process is confined with
  `/usr/bin/sandbox-exec` so that it can write only inside the staging
  directory. If `sandbox-exec` is unavailable, RARx logs a warning and falls
  back to staging-only protection.
- Staged symbolic links that point outside the staging directory are removed
  before the result is merged.
- Staged files with multiple hard links are rejected.
- Passwords are sent to UnRAR through stdin, never through command-line
  arguments. They are not written to logs.
- External commands are executed with argument arrays, not through a shell.
- Failed commits are rolled back where possible. If rollback itself fails, the
  staging directory is preserved and its path is reported to the user.

RARx does not use App Sandbox. The write confinement described above applies
only to the UnRAR child process; the application itself needs access to the
directory containing the archive in order to stage and merge files.

For vulnerability reporting and the full threat model, see
[`SECURITY.md`](SECURITY.md).

## Privacy

RARx does not contain telemetry, analytics, or update checks, and it does not
make network requests. Archive contents, passwords, and filenames stay on the
local machine. Diagnostic logs contain archive paths and UnRAR output, but never
passwords.

## Logs

- Path: `~/Library/Logs/RARx/RARx.log`
- Rotation: the current log is rotated to `RARx.log.1` at 2 MB.
- Passwords are not logged.

Logs may contain archive paths and filenames. Review them before sharing a log
in a public issue.

## Uninstall

```bash
pkill -x RARx 2>/dev/null || true
rm -rf /Applications/RARx.app
```

The LaunchServices handler association is stored per user and is not removed by
deleting the app. To use another application, select it for a `.rar` file in
Finder under **Open With > Other...**. Re-run the installer to restore RARx as
the handler.

Logs are not removed by the commands above. Delete `~/Library/Logs/RARx` if you
want to remove them.

## Project layout

```text
Sources/Core/      Extraction engine, process handling, staging, merging, safety
Sources/App/       Finder events, background queue, prompts, progress UI, settings
Resources/         Info.plist and localization resources
Tests/             Core tests and checked-in RAR fixtures
scripts/           Build, icon generation, installation, and test scripts
vendor/unrar/      UnRAR source and license
```

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the extraction transaction and
process model.

## Limitations

- RARx extracts RAR archives; it does not create them. The UnRAR license
  prohibits using its source to build a RAR-compatible archiver.
- The current conflict policy is always "keep both". There is no option to
  replace existing files.
- Archive entries stored as hard links are not preserved. Staged files with
  multiple hard links are removed by the safety validation.
- The application is ad-hoc signed and not notarized. The repository does not
  provide a Gatekeeper-ready binary.
- The optional password prompt may not receive keyboard focus automatically on
  macOS 14 and later because background apps cannot force activation. It is
  brought to the front; click the password field to focus it.
- macOS may show a folder-access prompt (TCC) the first time RARx extracts into
  a protected location such as Desktop, Documents, or Downloads.
- `sandbox-exec` is deprecated by Apple. RARx uses it as an additional
  mitigation, not as a substitute for App Sandbox or code review.
- Merging is not a single filesystem transaction. The common failure modes are
  rolled back, but a failure during rollback can leave a partially merged
  result and a preserved staging directory.
- RAR4/RAR5 support and legacy format behavior are inherited from UnRAR 7.13.
  The test suite focuses on RAR5 and does not exhaustively cover every legacy
  variant.
- The `x86_64` slice is built but has not been tested on Intel hardware or under
  Rosetta.

## Contributing

Contributions are welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for build,
test, and review requirements.

Do not report security vulnerabilities in a public issue. Use the private
reporting process described in [`SECURITY.md`](SECURITY.md).

## License

The original RARx source code is licensed under the **MIT License**. See
[`LICENSE`](LICENSE).

UnRAR is a separate component with its own license and is **not** covered by
the MIT License. Its complete license and attribution notice is in
[`THIRD_PARTY_NOTICES.txt`](THIRD_PARTY_NOTICES.txt). The same notice is included
in the application bundle at
`RARx.app/Contents/Resources/THIRD_PARTY_NOTICES.txt` and is available from
Settings.

RAR is a trademark of RARLAB. RARx is not affiliated with RARLAB.
