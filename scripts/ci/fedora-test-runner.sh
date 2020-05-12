#!/usr/bin/env bash

# TODO turn off v?
set -ev

echo "Gathering VM Status"
echo "Enforcing status: $(getenforce)"
echo "id: $(id -Z)"
echo "nproc: $(nproc)"
echo "cwd: $(pwd)"

# TODO Enable make -j builds
#let "jopt=$(nproc)*2+1"
#MAKE_J=make -j$(jopt)

dnf install -y \
    git \
    audit-libs-devel \
    bison \
    bzip2-devel \
    CUnit-devel \
    diffutils \
    flex \
    gcc \
    gettext \
    glib2-devel \
    make \
    libcap-devel \
    libcap-ng-devel \
    pam-devel \
    pcre-devel \
    xmlto \
    python3-devel \
    ruby-devel \
    swig \
    perl-Test \
    perl-Test-Harness \
    perl-Test-Simple \
    selinux-policy-devel \
    gcc \
    libselinux-devel \
    net-tools \
    netlabel_tools \
    iptables \
    lksctp-tools-devel \
    attr \
    libbpf-devel \
    keyutils-libs-devel \
    kernel-devel \
    quota \
    xfsprogs-devel \
    libuuid-devel \
    kernel-devel-$(uname -r) \
    kernel-modules-$(uname -r)

#
# Move to selinux code and build
#
cd ~/selinux

# Show HEAD commit for sanity checking
git log -1

#
# Build and replace userspace components
#
make LIBDIR=/usr/lib64 SHLIBDIR=/lib64 install install-pywrap relabel

#
# Get the selinux testsuite, but don't clone it in ~/selinux, move to ~
# first.
#
cd ~
git clone --depth=1 https://github.com/SELinuxProject/selinux-testsuite.git
cd selinux-testsuite

#
# Run the test suite
#
# TODO: Can these be run safely with make -j?
make test
