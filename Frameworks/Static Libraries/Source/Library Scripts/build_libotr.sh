#!/bin/bash

set -e

pushd "${LIBRARY_WORKING_DIRECTORY_LOCATION}"

curl -LO "https://otr.cypherpunks.ca/libotr-${LIBRARY_OTR_VERSION}.tar.gz" --retry 5

tar -xvf "./libotr-${LIBRARY_OTR_VERSION}.tar.gz"

mv "./libotr-${LIBRARY_OTR_VERSION}" "./libotr-source"

cd "./libotr-source"

case $ARCH in
	x86_64)
	HOST="x86_64-apple-darwin"
	;;
	arm64)
	HOST="aarch64-apple-darwin"
	;;
esac


export CC="clang"
export LDFLAGS="-mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET} -arch $ARCH -L${PREFIX_DIRECTORY_ARCH}/lib"
export CPPFLAGS="-Werror=partial-availability -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET} -arch $ARCH -isysroot ${PLATFORM_BUILD_SDK_ROOT_LOCATION} -I${PREFIX_DIRECTORY_ARCH}/include"
export CFLAGS="${CPPFLAGS}"
export CXXFLAGS="${CPPFLAGS}"

applyPatchesToLibrary "libotr"

./configure \
--host=$HOST \
--enable-static \
--disable-dependency-tracking \
--disable-shared \
--prefix="${PREFIX_DIRECTORY_ARCH}" \
--with-libgcrypt-prefix="${PREFIX_DIRECTORY_ARCH}"

make -j${BUILDJOBS}
make install

cp "${PREFIX_DIRECTORY_ARCH}/lib/libotr.a" "${STATICLIB_OUTPUT_DIR_ARCH}"

mkdir -p "${LICENSE_OUTPUT_DIR_ARCH}/libotr"

cp "./AUTHORS" "${LICENSE_OUTPUT_DIR_ARCH}/libotr"
cp "./COPYING" "${LICENSE_OUTPUT_DIR_ARCH}/libotr"
cp "./COPYING.LIB" "${LICENSE_OUTPUT_DIR_ARCH}/libotr"

popd
