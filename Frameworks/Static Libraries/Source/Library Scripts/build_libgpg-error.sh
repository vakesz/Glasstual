#!/bin/bash

set -e

pushd "${LIBRARY_WORKING_DIRECTORY_LOCATION}"

curl -LO "https://www.gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-${LIBRARY_GPG_ERROR_VERSION}.tar.bz2" --retry 5

tar -xvf "./libgpg-error-${LIBRARY_GPG_ERROR_VERSION}.tar.bz2"

mv "./libgpg-error-${LIBRARY_GPG_ERROR_VERSION}" "./libgpg-error-source"

cd "./libgpg-error-source"

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

applyPatchesToLibrary "libgpg-error"

./configure \
--host=$HOST \
--enable-static \
--disable-dependency-tracking \
--disable-silent-rules \
--prefix="${PREFIX_DIRECTORY_ARCH}"

make -j${BUILDJOBS}
make install

cp "${PREFIX_DIRECTORY_ARCH}/lib/libgpg-error.a" "${STATICLIB_OUTPUT_DIR_ARCH}"

mkdir -p "${LICENSE_OUTPUT_DIR_ARCH}/libgpg-error"

cp "./AUTHORS" "${LICENSE_OUTPUT_DIR_ARCH}/libgpg-error"
cp "./COPYING" "${LICENSE_OUTPUT_DIR_ARCH}/libgpg-error"
cp "./COPYING.LIB" "${LICENSE_OUTPUT_DIR_ARCH}/libgpg-error"
cp "./THANKS" "${LICENSE_OUTPUT_DIR_ARCH}/libgpg-error"

popd
