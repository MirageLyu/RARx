# Contributing to RARx

RARx is a small, native macOS project. Contributions that improve reliability,
security, documentation, or test coverage are welcome.

## Before opening an issue

- Search existing issues and pull requests first.
- Use the bug report or feature request template where possible.
- Redact passwords, usernames, private paths, and archive contents from logs and
  screenshots.
- Report security vulnerabilities privately as described in
  [`SECURITY.md`](SECURITY.md). Do not open a public issue for them.

## Development environment

Requirements:

- macOS 13 or later.
- The Swift toolchain from the Xcode Command Line Tools or Xcode.
- A logged-in GUI session for the Finder/LaunchServices integration tests.

Clone and build:

```bash
git clone https://github.com/MirageLyu/RARx.git
cd RARx
./scripts/build-app.sh
```

Run the full test suite:

```bash
./scripts/test.sh
```

The default test target is the freshly built `build/RARx.app`. To test an
installed copy, including its current LaunchServices registration:

```bash
APP=/Applications/RARx.app ./scripts/test.sh
```

The integration tests launch the real app through `open`. They do not run in a
headless environment.

## Design constraints

Please preserve these constraints unless the change explicitly revisits them:

- The app is a background application for Finder-driven extraction. Do not add a
  main window to the normal extraction path.
- Extraction code in `Sources/Core` must not depend on AppKit or SwiftUI.
- Archive contents remain untrusted. New file operations must go through the
  staging and validation pipeline.
- Existing files must never be overwritten by the merge.
- Do not add shell-based execution. Use `Process` with argument arrays.
- Passwords must not appear in command-line arguments, logs, preferences, crash
  reports, or network requests.
- Do not add telemetry, analytics, update checks, or network calls.
- The current build intentionally uses the Swift 5 language mode and system
  frameworks only. Avoid adding third-party runtime dependencies.
- Preserve cancellation and cleanup behavior for every new asynchronous path.

## Code style

- Match the existing Swift style and naming.
- Keep functions focused and prefer explicit error types over silent failure.
- Comments should explain why a safety measure exists, not restate the code.
- Avoid force unwraps in new code unless the invariant is local and obvious.
- Keep user-facing errors actionable. Raw UnRAR output belongs in the
  diagnostic log, not in place of a clear user message.
- Do not add debug output that may contain passwords, archive contents, or
  unredacted user data.
- Add user-facing strings through `L(...)`; do not hardcode display text in
  AppKit or SwiftUI views.

The application UI follows the macOS preferred language and currently supports
English and Simplified Chinese. User-facing strings use English source text as
their localization key and are wrapped with `L(...)`. Add the English entry to
`Resources/en.lproj/Localizable.strings` and the Simplified Chinese translation
to `Resources/zh-Hans.lproj/Localizable.strings`.

Run the localization check after changing a string:

```bash
swift scripts/check-localizations.swift .
```

The check verifies that both localization files contain every key used in
`Sources` and that format specifiers match. Additional languages are welcome as
focused changes that include all user-facing strings and an updated validation
baseline.

## Tests

- Add or update tests for behavior changes.
- Treat archive parsing, path handling, link handling, password handling, and
  file merging as security-sensitive code.
- Do not add personal archives or passwords to the repository. Use a minimal
  synthetic fixture that demonstrates the case.
- Run `./scripts/test.sh` before opening a pull request. It includes the
  localization check, core tests, and Finder integration tests.
- If a change cannot be covered by the existing suite, explain why in the pull
  request.

## Pull requests

A good pull request:

- Makes one coherent change.
- Describes the user-visible behavior and any security implications.
- Includes tests or explains why tests are not applicable.
- Updates the README or architecture document when behavior changes.
- Keeps generated artifacts out of version control. `build/` is ignored.
- Does not include credentials, personal paths, private archives, or logs with
  sensitive data.

Commit messages should use the imperative mood and a short subject, for example:

```text
Handle stale staging directories after a crash
```

## License

By contributing, you agree that your contribution is licensed under the MIT
License, the same license as the original RARx code. The UnRAR source and binary
remain under the separate UnRAR freeware license and are not relicensed by
contributions to RARx.

## Community expectations

Be respectful and constructive. Disagreement is fine; harassment, personal
attacks, and dismissive behavior are not. Maintainers may close issues or pull
requests that are unrelated, unsafe, or unproductive.
