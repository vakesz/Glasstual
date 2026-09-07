# DCC and notification platform verification

These are verification-only acceptance checks, not newly established
vulnerabilities. In particular, nothing here demonstrates missing quarantine
metadata. An unsigned standalone executable is not evidence for what the
signed, sandboxed application records.

## Local evidence

- Runtime: macOS 27.0, build 26A5425a, arm64.
- Compiler: Apple Swift 6.4, deployment target macOS 26, Swift 6 language mode,
  strict concurrency, default main-actor isolation.
- Standalone Swift Testing: 26 tests passed across DCC file actors, real
  temporary files, loopback transfers, and DCC CHAT sharing the timeout/listener
  helpers. No GUI session or application host was used.
- Hosted tests exercise controller resume, reverse sender offset retention,
  initialization stop, retired events, reverse lookup failure, notification
  destination selection, transfer identity matching, streamed HTTP response
  limits, speech mute, and backlog. They run with the rest of the suite under
  `make test`.

## File fixture

Use the same deterministic source as the loopback regression: 100,003 bytes,
byte at index `i` equal to `UInt8(truncatingIfNeeded: i * 31 + 7)`. The resume
fixture contains its first 37,003 bytes. Use `file.bin` as the wire name, and
pre-create an unrelated `file.bin` to exercise the local collision suffix.

For signed-app runs, capture the app build, signing identity, sandbox
entitlements, source/destination volume types, file sizes, SHA-256 checksums,
and extended-attribute names/values before transfer, after interruption, after
resume, and after completion. Quarantine values can contain timestamps and
agent identifiers; retain the raw fixture metadata as an artifact rather than
inventing a fixed expected byte string.

## Unverified boundaries

- Run the signed sandboxed app on macOS 26. The standalone macOS 27 execution
  does not replace minimum-supported-OS verification.
- Exercise a user-selected source outside the container with two recipients.
  Stop/remove one recipient while the other continues. Verify the second still
  reads its pinned source and access counts are balanced after final teardown.
- Exercise a user-selected destination and a persisted destination bookmark.
  Change the preferred folder during a transfer, terminate, relaunch, and test
  stale-bookmark recovery. Confirm retained partials remain accessible.
- Inspect quarantine and other OS-created metadata using the fixture above.
  Compare against the signed application's existing behavior. No quarantine
  vulnerability is claimed or marked fixed by the standalone tests.
- Exercise the actual Notification Center Accept button and body click, with
  permission granted and denied, a configured destination and the destination
  picker, active/completed/removed transfers, and a destroyed client.
- Confirm mute dismisses in-flight OS notification delivery and stops audible
  notification speech while explicit speech continues. Exercise asynchronous
  AVSpeechSynthesizer completion/cancellation and the real sound cache teardown.
- Verify interoperability with active and reverse peers, including clean
  ACKless transfers and cumulative 32-bit ACK wrap past 4 GiB. Loopback tests
  cover framing/wrap arithmetic, not every third-party client or NAT/router.
- Project generation, the application build, the hosted tests, lint and the
  sanitizer checks are the gate for this area: `make generate`, `make build`,
  `make lint`, `make test`, and locally `make tsan`. The standalone runs
  described above do not stand in for any of them.
