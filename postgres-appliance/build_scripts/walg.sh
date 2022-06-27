#!/bin/bash

## -------------------------
## Install wal-g
## -------------------------

export DEBIAN_FRONTEND=noninteractive

WALG_VERSION=v2.0.0

echo 'APT::Install-Recommends "0";\nAPT::Install-Suggests "0";' > /etc/apt/apt.conf.d/01norecommend

apt-get update
apt-get install -y curl ca-certificates

if [ "$(dpkg --print-architecture)" != "amd64" ]; then
    apt-get install -y software-properties-common
    add-apt-repository ppa:longsleep/golang-backports
    apt-get update
    apt-get install -y golang-go liblzo2-dev brotli libsodium-dev git make cmake gcc
    go version
fi

if [ "$(dpkg --print-architecture)" != "amd64" ]; then git clone -b $WALG_VERSION --recurse-submodules https://github.com/wal-g/wal-g.git; fi

cd /wal-g

if [ "$(dpkg --print-architecture)" != "amd64" ]; then go get -v -t -d ./... && go mod vendor; fi
if [ "$(dpkg --print-architecture)" != "amd64" ]; then export MAKEFLAGS="-j $(grep -c ^processor /proc/cpuinfo)" && bash link_brotli.sh; fi
if [ "$(dpkg --print-architecture)" != "amd64" ]; then export MAKEFLAGS="-j $(grep -c ^processor /proc/cpuinfo)" && bash link_libsodium.sh; fi
if [ "$(dpkg --print-architecture)" != "amd64" ]; then

if grep -q DISTRIB_RELEASE=18.04 /etc/lsb-release; then export CGO_LDFLAGS=-no-pie; fi
    export USE_LIBSODIUM=1
    export USE_LZO=1
    export MAKEFLAGS="-j $(grep -c ^processor /proc/cpuinfo)"
    make pg_build
fi

# We want to remove all libgdal20 debs except one that is for current architecture.
echo "shopt -s extglob\nrm /builddeps/!(*_$(dpkg --print-architecture).deb)" | bash -s

mkdir /builddeps/wal-g

if [ "$DEMO" = "true" ]; then
    rm -f /builddeps/*.deb
    # Create an empty dummy deb file to prevent the `COPY --from=dependencies-builder /builddeps/*.deb /builddeps/` step from failing
    touch /builddeps/dummy.deb
elif [ "$(dpkg --print-architecture)" != "amd64" ]; then
    cp /wal-g/main/pg/wal-g /builddeps/wal-g/
else
    # In order to speed up amd64 build we just download the binary from GH
    DISTRIB_RELEASE=$(sed -n 's/DISTRIB_RELEASE=//p' /etc/lsb-release)
    curl -sL https://github.com/wal-g/wal-g/releases/download/$WALG_VERSION/wal-g-pg-ubuntu-$DISTRIB_RELEASE-amd64.tar.gz \
                | tar -C /builddeps/wal-g -xz
    mv /builddeps/wal-g/wal-g-pg-ubuntu-$DISTRIB_RELEASE-amd64 /builddeps/wal-g/wal-g
fi
