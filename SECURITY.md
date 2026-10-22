# Security Policy

## Supported versions

| Version | Supported |
| --- | --- |
| 1.0.x | Yes |
| Earlier | No |

Security fixes are applied to the latest release on the `main` branch. Because
RARx is currently distributed as source and an ad-hoc signed local build, users
are expected to build or install the latest revision themselves.

## Reporting a vulnerability

**Do not open a public issue for a security vulnerability.**

Use GitHub's private vulnerability reporting:

<https://github.com/MirageLyu/RARx/security/advisories/new>

If private reporting is unavailable, contact the maintainer through the GitHub
profile at <https://github.com/MirageLyu> and request a private channel. Do not
include exploit details in a public thread.

A useful report includes:

- The RARx version or commit.
- The macOS version and Mac architecture.
- A description of the impact and the attacker's required access.
- Reproduction steps, ideally using a minimal synthetic archive.
- Relevant log lines with passwords, usernames, and private paths redacted.

Please avoid attaching a sensitive archive. If a reproducer needs an archive,
generate a minimal one that contains no private data. Never send a password
that you use for anything else.

Reports are handled on a best-effort basis. There is no bug bounty program and
no guaranteed response time, but good-faith reports will be acknowledged and
investigated.

## Scope

Security-relevant areas include:

- Archive path traversal or writes outside the staging directory.
- Symbolic-link or hard-link attacks that escape the staging boundary.
- Password disclosure through process arguments, logs, preferences, or crash
  reports.
- Command injection or unexpected shell execution.
- Unsafe stale-staging cleanup, including deleting active or unrelated data.
- Symlink attacks in the destination during the merge phase.
- LaunchServices behavior that causes RARx to open unintended files.
- Privilege escalation or bypass of the non-overwrite merge policy.
- Denial of service caused by a malformed archive that RARx should reject or
  contain.

Issues in UnRAR itself should be reported to RARLAB as well. If an UnRAR issue
affects RARx's threat model, include that context in the RARx report.

Out of scope for this policy:

- Attacks that require modifying the application bundle, running code as the
  same user, or already having administrator privileges.
- Social-engineering scenarios that do not involve RARx code or packaging.
- Reports that only demonstrate that `sandbox-exec` is deprecated by Apple.
- Issues that require the user to disable macOS security controls.

## Security model

RARx treats archives as untrusted. The implementation provides:

- Extraction into a hidden staging directory inside the destination.
- A write-confined UnRAR child process using `sandbox-exec` when available.
- Removal of symbolic links that resolve outside staging.
- Rejection of staged files with multiple hard links.
- Password transfer through stdin rather than command-line arguments.
- No shell invocation for external commands.
- A non-overwriting merge with a rollback journal.
- PID-locked stale-staging cleanup.
- No telemetry or network requests in the application.

RARx is **not** App Sandboxed. The application requires normal user file access
to read archives and merge staged results. The extraction child is confined, but
the application process itself has the privileges of the logged-in user.

For implementation details and failure semantics, see
[`ARCHITECTURE.md`](ARCHITECTURE.md).

## Good-faith research

Good-faith security research on your own machine is welcome. Avoid accessing
data that is not yours, disrupting other users, or publishing exploit details
before a fix is available. The maintainer will work in good faith with
researchers who follow responsible disclosure practices.
