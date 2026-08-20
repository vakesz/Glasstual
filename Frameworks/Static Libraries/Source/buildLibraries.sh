#!/bin/bash

REBUILD=false

export ARCHES=(x86_64 arm64)
export BUILDJOBS=$((  $(sysctl -n hw.ncpu) + 1))
export MACOSX_DEPLOYMENT_TARGET="10.13"
export PLATFORM_BUILD_SDK_ROOT_LOCATION=$(xcrun -sdk macosx --show-sdk-path)

export LIBRARY_LIBRESSL_VERSION="3.6.2"
export LIBRARY_GPG_ERROR_VERSION="1.42"
export LIBRARY_GCRYPT_VERSION="1.10.1"
export LIBRARY_OTR_VERSION="4.1.1"

export LIBRARIES_TO_BUILD=(libgpg-error libgcrypt libotr libressl)

export CURRENT_DIRECTORY=$(cd `dirname $0` && pwd)

export BUILDROOT_DIRECTORY="/tmp/static-library-build-results"
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

	find "${PATCH_DIRECTORY}" -name "*.patch" -print0 | while read -d $'\0' file
	do
		patch -p0 --ignore-whitespace < "${file}"
	done
}

export -f applyPatchesToLibrary

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
