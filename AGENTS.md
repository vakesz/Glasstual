# Repository Guidance

- Treat `project.yml` as the source of truth. Regenerate `Glasstual.xcodeproj` with `xcodegen generate --spec project.yml`; never edit the generated project by hand.
- Migrate toward a pure Swift codebase with no `.h`, `.m`, or `.c` implementation files. Keep temporary interoperability code only while an unmigrated consumer requires it.
- Keep first-party, service, plugin, and vendored source under `Sources/`; preserve every upstream copyright notice, license, and acknowledgement.
- Apply formatting and linting to the entire source tree. Fix diagnostics at their source instead of adding path exclusions or blanket suppressions.
- Before handing off code changes, regenerate the project and run the relevant build, tests, and `make lint`; report any boundary that was not exercised.
