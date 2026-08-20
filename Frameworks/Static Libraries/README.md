# Static libraries for Textual

### How this works

`Source/buildLibraries.sh` automates the building of libressl, libgpg-error, libgcrypt, and libotr for the Textual IRC Client.
By default, the build is done in `/tmp/static-library-build-results` (override with the `BUILDROOT_DIRECTORY` environment variable).

Current versions (all built for `arm64` only, `MACOSX_DEPLOYMENT_TARGET=26.0`, static only):

| Library | Version | Source | Used by |
| --- | --- | --- | --- |
| [LibreSSL](https://www.libressl.org) | 4.3.2 | https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/ | `libcrypto.a`: Blowfish Encryption plugin (DH/BN/SHA). `libssl.a`/`libtls.a` are built but not committed. |
| [libgpg-error](https://www.gnupg.org/software/libgpg-error/) | 1.61 | https://www.gnupg.org/ftp/gcrypt/libgpg-error/ | Encryption Kit (via libgcrypt/libotr) |
| [libgcrypt](https://www.gnupg.org/software/libgcrypt/) | 1.11.3 | https://www.gnupg.org/ftp/gcrypt/libgcrypt/ | Encryption Kit (via libotr) |
| [libotr](https://otr.cypherpunks.ca) | 4.1.1 | https://otr.cypherpunks.ca/ | Encryption Kit |

The build script pins the SHA256 of every release tarball (`LIBRARY_*_SHA256` in `buildLibraries.sh`) and refuses to extract an archive that does not match. When bumping a version, take the new checksum from the mirror (`SHA256` file for LibreSSL, the gnupg.org integrity page or the GPG `.sig` for the GnuPG libraries) and verify the GPG signature of the tarball before updating the pinned value.

Other libraries and frameworks are obtained prebuilt or built manually.

Prebuilt:
- [Sparkle.framework 2.6.4](https://github.com/sparkle-project/Sparkle/)

Built manually:
- [asn1c 0.9.28](https://github.com/vlm/asn1c) (used by Apple Receipt Loader, built using `Libraries/Source/Apple Receipt ASN1c/asn1c.xcodeproj`)
- [GRMustache af9d138f6fc1d985a2c4089ad19b791a02827908](https://github.com/groue/GRMustache) (templating engine, built using `Libraries/Source/GRMustache/GRMustache.xcodeproj`)

## Main Libraries

### How to build

This repository contains prebuilt binaries; however, if you need to rebuild them, instructions follow.
This assumes the arch being built is the default (`arm64` only). The `ARCHES` and `MACOSX_DEPLOYMENT_TARGET` variables can be changed in the `buildLibraries.sh` script; with more than one arch the script also produces `lipo`-combined libraries in `lib-static/universal`.

The build only needs Xcode's command line tools (clang, make, lipo). No Homebrew packages are required; Homebrew binaries must not be used for the libraries themselves because the app needs static libraries built with a controlled minimum macOS version.

1. `cd Source`
2. `./buildLibraries.sh`
3. Ensure that `/tmp/static-library-build-results/lib-static/arm64` contains the following files:
   - libcrypto.a
   - libgcrypt.a
   - libgpg-error.a
   - libotr.a
   - libssl.a
   - libtls.a
4. Copy `libcrypto.a`, `libgcrypt.a`, `libgpg-error.a`, and `libotr.a` into the `Libraries` directory in this repository, overwriting the existing libraries. Do not commit `libssl.a` or `libtls.a`; nothing links them.
5. Verify the products:
   - `lipo -archs Libraries/libcrypto.a` prints `arm64`
   - `otool -l Libraries/libcrypto.a | grep -A3 LC_BUILD_VERSION` shows `platform 1` and `minos 26.0` for every object


## How to update library versions
Modify `Source/buildLibraries.sh` to have the desired library version numbers and tarball checksums. Note that this might break the build and might require additional patches (put `*.patch` files, `-p0`, under `Source/Library Script Patches/<library>/`; they are applied before `configure`). libgcrypt must be built against the matching libgpg-error and libotr against that libgcrypt; the script builds them in that order against its own prefix.

After building the libraries, the following additional steps must be taken:
1. If more than one arch is built, verify that there are no critical differences between the headers for the different arches:
   
   `diff -Nruw /tmp/static-library-build-results/includes/x86_64 /tmp/static-library-build-results/includes/arm64`
   
   A slight difference in the comment header in `gpgrt.h` is expected.
2. Delete the `Headers/libotr` and the `Headers/openssl` directories in this repository.
3. Copy everything inside `/tmp/static-library-build-results/includes/arm64/` into `Headers` in this repository.
4. When completed, `Headers` should contain the following files:
   - gcrypt.h
   - gpg-error.h
   - gpgrt.h
   - tls.h

   And the following directories:
   - libmustache
   - libotr
   - openssl
5. Delete the following directories within `Documentation` in this repository:
   - libgcrypt
   - libgpg-error
   - libotr
   - libssl
6. Copy everything inside `/tmp/static-library-build-results/licenses/arm64/` to `Documentation`.
7. Build the app (`xcodebuild -scheme Glasstual`) so that Encryption Kit is compiled and linked against the new headers and libraries, and make corrections for any API changes.
8. The Blowfish Encryption plugin is not part of the Xcode project, so compile-check it by hand against the new `openssl` headers, for example:

   `xcrun clang++ -fsyntax-only -fobjc-arc -std=gnu++20 -I "Frameworks/Static Libraries/Headers" -I "Sources/Plugins/Blowfish Encryption/Classes" -I <dir containing a CocoaExtensions -> "Frameworks/Cocoa Extensions/Classes" symlink> "Sources/Plugins/Blowfish Encryption/Classes/BlowfishEncryptionKeyExchangeBase.mm"`


## Other Libraries

For the prebuilt libraries, just download the latest releases and copy the frameworks into `Libraries`.

For the libraries built manually, instructions follow.

### libasn1: 

1. Build `Source/Apple Receipt ASN1c/asn1c.xcodeproj`.
2. Copy the `libasn1c.a`  build product into `Libraries`.

Updating this library is somewhat complicated -- files need to be copied from the source package and the Xcode project needs to be modified appropriately.

### GRMustache:

1. Check out the source code from GitHub.
2. Open `src/GRMustache.xcodeproj`, set the project to "GRMustache7-MacOS", and set build to "Any Mac".
3. Go to Project Info and set the Deployment Target to macOS 10.12.
4. Close the Xcode project.
5. Open Terminal, cd to the directory for GRMustache, and run `make lib/libGRMustache7-MacOS.a`.
6. Copy `lib/libGRMustache7-MacOS.a` to `Source/GRMustache/Libraries/libmustache.a` in this repo.
7. If you are building a different version of GRMustache, you will need to copy over the headers to `Source/GRMustache/Headers` and ensure that there have been no substantial changes.
8. Open `Sources/GRMustache/GRMustache.xcodeproj` in this repo.
9. Build the GRMustache wrapper.
10. Copy the `GRMustache.framework` build product to the `Libraries` directory in this repo.

## Licensing

See the `Documentation` directory.
