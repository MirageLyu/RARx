# Changelog

All notable changes to RARx are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-10-22

### Added

- English and Simplified Chinese interface localization that follows the macOS
  preferred language.
- Automatic fallback to English for unsupported system languages.
- Localization key and format-specifier validation in the test suite.
- Architecture, security, contribution, and changelog documentation.
- GitHub issue templates and a pull request template.

### Changed

- Rewrote the README and project documentation in English.
- Renamed the third-party notice file to `THIRD_PARTY_NOTICES.txt`.
- Updated the application version to 1.1.0 (build 2).

### Fixed

- Password and error prompts are centered on the active display and moved to
  the active Space before presentation.
- Settings descriptions wrap correctly at longer English lengths.

## [1.0.0] - 2026-10-22

### Added

- Finder-driven background extraction for `.rar` archives using LaunchServices.
- Background queue for multiple archives from a single open event.
- Automatic first-volume resolution when a later `partN.rar` volume is opened.
- Password support for encrypted headers and encrypted file data.
- Password retry flow with a limit of three failed attempts.
- Non-destructive conflict handling that preserves existing files and renames
  incoming conflicts with numbered suffixes.
- Hidden staging directories with disk-space checks and PID-locked stale-stage
  cleanup.
- Write confinement for the UnRAR child process through `sandbox-exec`.
- Validation and removal of escaping symbolic links and staged files with
  multiple hard links.
- Rollback journal for the merge phase and preservation of staging data when
  rollback cannot complete.
- Optional non-activating progress panel with cancellation.
- Application and `.rar` document icons.
- Settings window for default-handler registration, progress behavior, sound,
  logs, and license notices.
- Rotating diagnostic log at `~/Library/Logs/RARx/RARx.log`.

### Security

- Passwords are delivered to UnRAR over stdin and are never placed in process
  arguments or logs.
- UnRAR is invoked without a shell.
- Untrusted staged links are validated before merging.
- The app does not contain telemetry or network code.

### Documentation

- Added the initial README.
- Added the MIT license for original RARx code and separate UnRAR third-party
  notices.

[Unreleased]: https://github.com/MirageLyu/RARx/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/MirageLyu/RARx/releases/tag/v1.1.0
[1.0.0]: https://github.com/MirageLyu/RARx/releases/tag/v1.0.0
