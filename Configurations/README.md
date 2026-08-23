# Build configuration

`Glasstual.xcodeproj` is generated from `project.yml` at the repository root
with [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew bundle`
installs it). Edit the spec or the files in this directory, then run:

```sh
xcodegen generate
```

The generated project is committed so the tree builds without XcodeGen, but
never edit it directly: the next `xcodegen generate` overwrites it.

## Files

- `Signing.xcconfig` is the only file a contributor edits. It sets the code
  signing style, identity, and Team ID for every target. CI overrides these
  on the `xcodebuild` command line for Developer ID builds.
- `Base.xcconfig` holds every setting shared by all targets: product
  identity, feature flags, language modes, warnings, and build behaviour.
- `Debug.xcconfig` and `Release.xcconfig` include `Base.xcconfig` and change
  optimisation, assertions, and hardened runtime. These are the only two
  build configurations.
- `Version.generated.xcconfig` is written by `Scripts/UpdateVersion.sh` (a
  pre-action of the `Glasstual` scheme) and is ignored by git. It sets
  `CURRENT_PROJECT_VERSION` to the date of the last commit (`yymmdd.HH`),
  which becomes `CFBundleVersion`. `MARKETING_VERSION` (the user facing
  version) lives in `Base.xcconfig`. Without the generated file the version
  falls back to `0`.
- `Sandbox/Inherited.entitlements` is used by the bundled extensions and the
  Core Media plugin. The app and each XPC service keep their own entitlements
  next to their sources.

## Build configuration header

There are no feature flags. The `BuildConfig` aggregate target
(`Scripts/GenerateBuildConfig.sh`) writes `BuildConfig.h` (bundle identifier,
group container, version) for the code that includes that header.

The app is always built sandboxed and for `arm64` only; there are no flags
for either.

## Targets

The app, the two frameworks, the three XPC services, the Core Media plugin,
and the six bundled extensions are all targets of the single project with
real dependencies and embed phases. The app's product name and bundle
identifier come from `GLASSTUAL_PRODUCT_NAME` and
`GLASSTUAL_BUNDLE_IDENTIFIER` in `Base.xcconfig`; the group container is
derived from `DEVELOPMENT_TEAM`.
