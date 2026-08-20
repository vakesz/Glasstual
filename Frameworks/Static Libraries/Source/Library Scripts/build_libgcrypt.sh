#!/bin/bash

set -e

pushd "${LIBRARY_WORKING_DIRECTORY_LOCATION}"

curl -LO "https://www.gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-${LIBRARY_GCRYPT_VERSION}.tar.bz2"  --retry 5

tar -xvf "./libgcrypt-${LIBRARY_GCRYPT_VERSION}.tar.bz2"

mv "./libgcrypt-${LIBRARY_GCRYPT_VERSION}" "./libgcrypt-source"

cd "./libgcrypt-source"

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

applyPatchesToLibrary "libgcrypt"

./configure \
--host=$HOST \
--enable-static \
--disable-asm \
--disable-dependency-tracking \
--disable-silent-rules \
--prefix="${PREFIX_DIRECTORY_ARCH}" \
--with-libgpg-error-prefix="${PREFIX_DIRECTORY_ARCH}"

make -j${BUILDJOBS}
make install

cp "${PREFIX_DIRECTORY_ARCH}/lib/libgcrypt.a" "${STATICLIB_OUTPUT_DIR_ARCH}"

mkdir -p "${LICENSE_OUTPUT_DIR_ARCH}/libgcrypt"

cp "./AUTHORS" "${LICENSE_OUTPUT_DIR_ARCH}/libgcrypt"
cp "./COPYING" "${LICENSE_OUTPUT_DIR_ARCH}/libgcrypt"
cp "./COPYING.LIB" "${LICENSE_OUTPUT_DIR_ARCH}/libgcrypt"
cp "./LICENSES" "${LICENSE_OUTPUT_DIR_ARCH}/libgcrypt"
cp "./THANKS" "${LICENSE_OUTPUT_DIR_ARCH}/libgcrypt"

popd
