#!/bin/bash

set -e

pushd "${LIBRARY_WORKING_DIRECTORY_LOCATION}"

curl -LO "http://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-${LIBRARY_LIBRESSL_VERSION}.tar.gz" --retry 5

tar -xvf "./libressl-${LIBRARY_LIBRESSL_VERSION}.tar.gz"

mv "./libressl-${LIBRARY_LIBRESSL_VERSION}" "./libressl-source"

cd "./libressl-source"

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

applyPatchesToLibrary "libressl"

# ac_cv_func_strtonum - disable use of strtonum which is only available on macOS 11 but is misdetected
./configure \
ac_cv_func_strtonum=no \
ac_cv_func_timingsafe_bcmp=no \
--host=$HOST \
--enable-static \
--disable-dependency-tracking \
--disable-silent-rules \
--disable-shared \
--prefix="${PREFIX_DIRECTORY_ARCH}"

make -j${BUILDJOBS}
make install

cp "${PREFIX_DIRECTORY_ARCH}/lib/libcrypto.a" "${STATICLIB_OUTPUT_DIR_ARCH}"
cp "${PREFIX_DIRECTORY_ARCH}/lib/libssl.a" "${STATICLIB_OUTPUT_DIR_ARCH}"
cp "${PREFIX_DIRECTORY_ARCH}/lib/libtls.a" "${STATICLIB_OUTPUT_DIR_ARCH}"

mkdir -p "${LICENSE_OUTPUT_DIR_ARCH}/libressl"

cp "./COPYING" "${LICENSE_OUTPUT_DIR_ARCH}/libressl"

popd
