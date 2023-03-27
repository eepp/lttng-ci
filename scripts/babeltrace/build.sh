#!/bin/bash
#
# Copyright (C) 2015 Jonathan Rajotte-Julien <jonathan.rajotte-julien@efficios.com>
# Copyright (C) 2016-2020 Michael Jeanson <mjeanson@efficios.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

set -exu

# Version compare functions
vercomp () {
    set +u
    if [[ "$1" == "$2" ]]; then
        return 0
    fi
    local IFS=.
    # Ignore the shellcheck warning, we want splitting to happen based on IFS.
    # shellcheck disable=SC2206
    local i ver1=($1) ver2=($2)
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 2
        fi
    done
    set -u
    return 0
}

# Shellcheck flags the following functions that are unused as "unreachable",
# ignore that.

# shellcheck disable=SC2317
verlte() {
    vercomp "$1" "$2"
    local res="$?"
    [ "$res" -eq "0" ] || [ "$res" -eq "2" ]
}

# shellcheck disable=SC2317
verlt() {
    vercomp "$1" "$2"; local res="$?"
    [ "$res" -eq "2" ]
}

# shellcheck disable=SC2317
vergte() {
    vercomp "$1" "$2"; local res="$?"
    [ "$res" -eq "0" ] || [ "$res" -eq "1" ]
}

# shellcheck disable=SC2317
vergt() {
    vercomp "$1" "$2"; local res="$?"
    [ "$res" -eq "1" ]
}

# shellcheck disable=SC2317
verne() {
    vercomp "$1" "$2"; local res="$?"
    [ "$res" -ne "0" ]
}

failed_configure() {
    # Assume we are in the configured build directory
    echo "#################### BEGIN config.log ####################"
    cat config.log
    echo "#################### END config.log ####################"
    exit 1
}


# Required variables
WORKSPACE=${WORKSPACE:-}

platform=${platform:-}
conf=${conf:-}
build=${build:-}
cc=${cc:-}

# Controls if the tests are run
BABELTRACE_RUN_TESTS="${BABELTRACE_RUN_TESTS:=yes}"

SRCDIR="$WORKSPACE/src/babeltrace"
TMPDIR="$WORKSPACE/tmp"
PREFIX="/build"
LIBDIR="lib"
LIBDIR_ARCH="$LIBDIR"

# RHEL and SLES both use lib64 but don't bother shipping a default autoconf
# site config that matches this.
if [[ ( -f /etc/redhat-release || -f /etc/products.d/SLES.prod || -f /etc/yocto-release ) ]]; then
    # Detect the userspace bitness in a distro agnostic way
    if file -L /bin/bash | grep '64-bit' >/dev/null 2>&1; then
        LIBDIR_ARCH="${LIBDIR}64"
    fi
fi

# Create tmp directory
rm -rf "$TMPDIR"
mkdir -p "$TMPDIR"

export TMPDIR
export CFLAGS="-g -O2"

# Set compiler variables
case "$cc" in
gcc)
    export CC=gcc
    export CXX=g++
    ;;
gcc-*)
    export CC=gcc-${cc#gcc-}
    export CXX=g++-${cc#gcc-}
    ;;
clang)
    export CC=clang
    export CXX=clang++
    ;;
clang-*)
    export CC=clang-${cc#clang-}
    export CXX=clang++-${cc#clang-}
    ;;
*)
    if [ "x$cc" != "x" ]; then
	    export CC="$cc"
    fi
    ;;
esac

if [ "x${CC:-}" != "x" ]; then
    echo "Selected compiler:"
    "$CC" -v
fi

# Set platform variables
case "$platform" in
macos*)
    export MAKE=make
    export TAR=tar
    export NPROC="getconf _NPROCESSORS_ONLN"
    export PATH="/opt/local/bin:/opt/local/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    export CPPFLAGS="-I/opt/local/include"
    export LDFLAGS="-L/opt/local/lib"
    export PYTHON="python3"
    export PYTHON_CONFIG="python3-config"
    ;;

freebsd*)
    export MAKE=gmake
    export TAR=tar
    export NPROC="getconf _NPROCESSORS_ONLN"
    export CPPFLAGS="-I/usr/local/include"
    export LDFLAGS="-L/usr/local/lib"
    export PYTHON="python3"
    export PYTHON_CONFIG="python3-config"

    # For bt 1.5
    export YACC="bison -y"
    ;;

*)
    export MAKE=make
    export TAR=tar
    export NPROC=nproc
    export PYTHON="python3"
    export PYTHON_CONFIG="python3-config"
    ;;
esac

# Print build env details
print_os || true
print_tooling || true

# Enter the source directory
cd "$SRCDIR"

# Run bootstrap in the source directory prior to configure
./bootstrap

# Get source version from configure script
eval "$(grep '^PACKAGE_VERSION=' ./configure)"
PACKAGE_VERSION=${PACKAGE_VERSION//\-pre*/}

# Enable dev mode by default for BT 2.0 builds
export BABELTRACE_DEBUG_MODE=1
export BABELTRACE_DEV_MODE=1
export BABELTRACE_MINIMAL_LOG_LEVEL=TRACE

# Set configure options and environment variables for each build
# configuration.
CONF_OPTS=("--prefix=$PREFIX" "--libdir=$PREFIX/$LIBDIR_ARCH")

# -Werror is enabled by default in stable-2.0 but won't be in 2.1
# Explicitly disable it for consistency.
if vergte "$PACKAGE_VERSION" "2.0"; then
	CONF_OPTS+=("--disable-Werror")
fi

case "$conf" in
static)
    echo "Static lib only configuration"

    CONF_OPTS+=("--enable-static" "--disable-shared")

    if vergte "$PACKAGE_VERSION" "2.0"; then
        CONF_OPTS+=("--enable-built-in-plugins")
    fi
    ;;

python-bindings)
    echo "Python bindings configuration"

    CONF_OPTS+=("--enable-python-bindings")

    if vergte "$PACKAGE_VERSION" "2.0"; then
        CONF_OPTS+=("--enable-python-bindings-doc" "--enable-python-plugins")
    fi
    ;;

prod)
    echo "Production configuration"

    # Unset the developper variables
    unset BABELTRACE_DEBUG_MODE
    unset BABELTRACE_DEV_MODE
    unset BABELTRACE_MINIMAL_LOG_LEVEL

    # Enable the python bindings
    CONF_OPTS+=("--enable-python-bindings" "--enable-python-plugins")
    ;;

doc)
    echo "Documentation configuration"

    CONF_OPTS+=("--enable-python-bindings" "--enable-python-bindings-doc" "--enable-python-plugins" "--enable-api-doc")
    ;;

asan)
    echo "Address Sanitizer configuration"

    # --enable-asan was introduced after 2.0 but don't check the version, we
    # want this configuration to fail if ASAN is unavailable.
    CONF_OPTS+=("--enable-asan" "--enable-python-bindings" "--enable-python-plugins")
    ;;

min)
    echo "Minimal configuration"
    ;;

*)
    echo "Standard configuration"

    # Enable the python bindings / plugins by default with babeltrace2,
    # the test suite is mostly useless without it.
    if vergte "$PACKAGE_VERSION" "2.0"; then
        CONF_OPTS+=("--enable-python-bindings" "--enable-python-plugins")
    fi

    # Something is broken in docbook-xml on yocto
    if [[ "$platform" = yocto* ]]; then
        CONF_OPTS+=("--disable-man-pages")
    fi
    ;;
esac

# Build type
# oot     : out-of-tree build
# dist    : build via make dist
# oot-dist: build via make dist out-of-tree
# *       : normal tree build
#
# Make sure to move to the build directory and run configure
# before continuing.
case "$build" in
oot)
    echo "Out of tree build"

    # Create and enter a temporary build directory
    builddir=$(mktemp -d)
    cd "$builddir"

    "$SRCDIR/configure" "${CONF_OPTS[@]}" || failed_configure
    ;;

dist)
    echo "Distribution in-tree build"

    # Run configure and generate the tar file
    # in the source directory
    ./configure || failed_configure
    $MAKE dist

    # Create and enter a temporary build directory
    builddir=$(mktemp -d)
    cd "$builddir"

    # Extract the distribution tar in the build directory,
    # ignore the first directory level
    $TAR xvf "$SRCDIR"/*.tar.* --strip 1

    # Build in extracted source tree
    ./configure "${CONF_OPTS[@]}" || failed_configure
    ;;

oot-dist)
    echo "Distribution out of tree build"

    # Create and enter a temporary build directory
    builddir=$(mktemp -d)
    cd "$builddir"

    # Run configure out of tree and generate the tar file
    "$SRCDIR/configure" || failed_configure
    $MAKE dist

    dist_srcdir="$(mktemp -d)"
    cd "$dist_srcdir"

    # Extract the distribution tar in the new source directory,
    # ignore the first directory level
    $TAR xvf "$builddir"/*.tar.* --strip 1

    # Create and enter a second temporary build directory
    builddir="$(mktemp -d)"
    cd "$builddir"

    # Run configure from the extracted distribution tar,
    # out of the source tree
    "$dist_srcdir/configure" "${CONF_OPTS[@]}" || failed_configure
    ;;

*)
    echo "Standard in-tree build"
    ./configure "${CONF_OPTS[@]}" || failed_configure
    ;;
esac

# We are now inside a configured build directory

# BUILD!
$MAKE -j "$($NPROC)" V=1

# Install in the workspace
$MAKE install DESTDIR="$WORKSPACE"

# Run tests, don't fail now, we want to run the archiving steps
failed_tests=0
if [ "$BABELTRACE_RUN_TESTS" = "yes" ]; then
	$MAKE --keep-going check || failed_tests=1

	# Copy tap logs for the jenkins tap parser before cleaning the build dir
	rsync -a --exclude 'test-suite.log' --include '*/' --include '*.log' --exclude='*' tests/ "$WORKSPACE/tap"

	# Copy the test suites top-level log which includes all tests failures
	rsync -a --include 'test-suite.log' --include '*/' --exclude='*' tests/ "$WORKSPACE/log"

	# The test suite prior to 1.5 did not produce TAP logs
	if verlt "$PACKAGE_VERSION" "1.5"; then
	    mkdir -p "$WORKSPACE/tap/no-log"
	    echo "1..1" > "$WORKSPACE/tap/no-log/tests.log"
	    echo "ok 1 - Test suite doesn't support logging" >> "$WORKSPACE/tap/no-log/tests.log"
	fi
fi

# Clean the build directory
$MAKE clean

# Cleanup rpath in executables and shared libraries
find "$WORKSPACE/$PREFIX/bin" -type f -perm -0500 -exec chrpath --delete {} \;
find "$WORKSPACE/$PREFIX/$LIBDIR_ARCH" -name "*.so" -exec chrpath --delete {} \;

# Remove libtool .la files
find "$WORKSPACE/$PREFIX/$LIBDIR_ARCH" -name "*.la" -exec rm -f {} \;

# Exit with failure if any of the tests failed
exit $failed_tests

# EOF
