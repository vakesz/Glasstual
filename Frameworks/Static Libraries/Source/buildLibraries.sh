#!/bin/bash

REBUILD=false

export ARCHES=(arm64)
export BUILDJOBS=$((  $(sysctl -n hw.ncpu) + 1))
export MACOSX_DEPLOYMENT_TARGET="26.0"
export PLATFORM_BUILD_SDK_ROOT_LOCATION=$(xcrun -sdk macosx --show-sdk-path)

# Versions and the SHA256 of the release tarballs. The checksums were taken from
# the official mirrors (LibreSSL: ftp.openbsd.org SHA256 file; GnuPG: release
# .sig files / gnupg.org integrity page; libotr: .asc signature) and are
# verified before the archives are extracted.
export LIBRARY_LIBRESSL_VERSION="4.3.2"
export LIBRARY_LIBRESSL_SHA256="edf01aee24c65d69e6a9efcb9d44bcda682ff9d4f3bbbd95e794e1dfa90847b5"
export LIBRARY_GPG_ERROR_VERSION="1.61"
export LIBRARY_GPG_ERROR_SHA256="7a85413f2bc354f4f8aa832b718af122e48965e9e0eb9012ee659c13c6385c93"
export LIBRARY_GCRYPT_VERSION="1.11.3"
export LIBRARY_GCRYPT_SHA256="2c6d562e894b2b06eefbc427d12d51ee9d3e50e90012ad6596b4cb3e421a95f2"
export LIBRARY_OTR_VERSION="4.1.1"
export LIBRARY_OTR_SHA256="8b3b182424251067a952fb4e6c7b95a21e644fbb27fbd5f8af2b2ed87ca419f5"

export LIBRARIES_TO_BUILD=(libgpg-error libgcrypt libotr libressl)

export CURRENT_DIRECTORY=$(cd `dirname $0` && pwd)

export BUILDROOT_DIRECTORY="${BUILDROOT_DIRECTORY:-/tmp/static-library-build-results}"
export PREFIX_DIRECTORY="${BUILDROOT_DIRECTORY}/Library-Build-Results"
export WORKING_DIRECTORY="${BUILDROOT_DIRECTORY}/Library-Build-Source"
export STATICLIB_OUTPUT_DIR="${BUILDROOT_DIRECTORY}/lib-static"
export HEADER_OUTPUT_DIR="${BUILDROOT_DIRECTORY}/includes"
export LICENSE_OUTPUT_DIR="${BUILDROOT_DIRECTORY}/licenses"

STATICLIB_OUTPUT_DIR_UNIVERSAL="${STATICLIB_OUTPUT_DIR}/universal"

function deleteOldAndCreateDirectory {
	if [ -d "$1" ]; then
		rm -rf "$1"
	fi

	mkdir -p "$1"
}

function applyPatchesToLibrary {
	PATCH_DIRECTORY="${CURRENT_DIRECTORY}/Library Script Patches/$1"

	if [ ! -d "${PATCH_DIRECTORY}" ]; then
		return 0
	fi

	find "${PATCH_DIRECTORY}" -name "*.patch" -print0 | while read -d $'\0' file
	do
		patch -p0 --ignore-whitespace < "${file}"
	done
}

export -f applyPatchesToLibrary

# verifyChecksum <file> <expected sha256>
function verifyChecksum {
	ACTUAL=$(shasum -a 256 "$1" | awk '{print $1}')

	if [ "${ACTUAL}" != "$2" ]; then
		echo "Checksum mismatch for $1"
		echo "  expected: $2"
		echo "  actual:   ${ACTUAL}"
		exit 1
	fi

	echo "Checksum OK for $1"
}

export -f verifyChecksum

STDPATH=${PATH} # save the path as we will be adding to it later

if [ "$REBUILD" = true ]; then 
	deleteOldAndCreateDirectory "${STATICLIB_OUTPUT_DIR}"
	deleteOldAndCreateDirectory "${HEADER_OUTPUT_DIR}"
	deleteOldAndCreateDirectory "${LICENSE_OUTPUT_DIR}"
fi

for ARCH in ${ARCHES[@]}; do
	export PREFIX_DIRECTORY_ARCH="${PREFIX_DIRECTORY}/$ARCH"
	export WORKING_DIRECTORY_ARCH="${BUILDROOT_DIRECTORY}/Library-Build-Source/${ARCH}"
	export STATICLIB_OUTPUT_DIR_ARCH="${STATICLIB_OUTPUT_DIR}/${ARCH}"
	export HEADER_OUTPUT_DIR_ARCH="${HEADER_OUTPUT_DIR}/${ARCH}"
	export LICENSE_OUTPUT_DIR_ARCH="${LICENSE_OUTPUT_DIR}/${ARCH}"

	# these dirs have the final build products for this arch, we need to keep it around
	mkdir -p "${STATICLIB_OUTPUT_DIR_ARCH}"
	mkdir -p "${HEADER_OUTPUT_DIR_ARCH}"
	mkdir -p "${LICENSE_OUTPUT_DIR_ARCH}"

	LIBRARIES_THAT_DONT_EXIST=()

	for LIBRARY_TO_BUILD in ${LIBRARIES_TO_BUILD[@]}
	do
		if [ ${LIBRARY_TO_BUILD} = "libressl" ]; then
			if [ ! -f "${STATICLIB_OUTPUT_DIR_ARCH}/libcrypto.a" ] || [ ! -f "${STATICLIB_OUTPUT_DIR_ARCH}/libssl.a" ] || [ ! -f "${STATICLIB_OUTPUT_DIR_ARCH}/libtls.a" ]; then
			LIBRARIES_THAT_DONT_EXIST+=("${LIBRARY_TO_BUILD}")
		fi

		elif [ ! -f "${STATICLIB_OUTPUT_DIR_ARCH}/${LIBRARY_TO_BUILD}.a" ]; then
			LIBRARIES_THAT_DONT_EXIST+=("${LIBRARY_TO_BUILD}")
		fi
	done

	if [ ${#LIBRARIES_THAT_DONT_EXIST[@]} == 0 ]; then
		echo "Everything has previously been built for $ARCH..."
		continue;
	fi

	deleteOldAndCreateDirectory "${PREFIX_DIRECTORY_ARCH}"
	deleteOldAndCreateDirectory "${WORKING_DIRECTORY_ARCH}"

	# open "${ROOT_DIRECTORY}"

	for LIBRARY_TO_BUILD in ${LIBRARIES_THAT_DONT_EXIST[@]}
	do
		export PATH="${STDPATH}:${PREFIX_DIRECTORY_ARCH}/bin"

		export LIBRARY_WORKING_DIRECTORY_LOCATION="${WORKING_DIRECTORY_ARCH}/${LIBRARY_TO_BUILD}/"

		export COMMAND_MODE=unix2003

		deleteOldAndCreateDirectory "${LIBRARY_WORKING_DIRECTORY_LOCATION}"

		export ARCH

		"${CURRENT_DIRECTORY}/Library Scripts/build_${LIBRARY_TO_BUILD}.sh"
	done

	cp -a "${PREFIX_DIRECTORY_ARCH}/include"/* ${HEADER_OUTPUT_DIR_ARCH}
done

if [ ${#ARCHES[@]} -lt "2" ]; then
	echo "Libraries have been built for one architecture: ${ARCHES[*]}"
	echo "Build products are in ${STATICLIB_OUTPUT_DIR_ARCH}."

	exit 0
fi

# combine the libs
if [ "$REBUILD" = true ]; then
	deleteOldAndCreateDirectory "${STATICLIB_OUTPUT_DIR_UNIVERSAL}"
else
	mkdir -p "${STATICLIB_OUTPUT_DIR_UNIVERSAL}"
fi

LIBFILE_NAMES=("${LIBRARIES_TO_BUILD[@]//libressl/libcrypto libssl libtls}")

for LIBRARY_TO_BUILD in ${LIBFILE_NAMES[@]}
do
	echo $LIBRARY_TO_BUILD

	if [ ! -f "${STATICLIB_OUTPUT_DIR_UNIVERSAL}/${LIBRARY_TO_BUILD}.a" ]; then
		LIBS=""

		for ARCH in ${ARCHES[@]}; do
			LIBS="${LIBS} ${STATICLIB_OUTPUT_DIR}/${ARCH}/${LIBRARY_TO_BUILD}.a"
		done

		echo $LIBS
		echo "${STATICLIB_OUTPUT_DIR_UNIVERSAL}/${LIBRARY_TO_BUILD}.a"

		# combine the lib
		lipo -create ${LIBS} -output "${STATICLIB_OUTPUT_DIR_UNIVERSAL}/${LIBRARY_TO_BUILD}.a"
	fi
done

echo "Libraries exist as universal binaries for the following architectures: ${ARCHES[*]}"
echo "Build products are in ${STATICLIB_OUTPUT_DIR_UNIVERSAL}."
