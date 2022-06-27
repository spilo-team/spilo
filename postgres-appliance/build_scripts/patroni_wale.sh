#!/bin/bash

## -------------------------
## Install patroni and wal-e
## -------------------------

export DEBIAN_FRONTEND=noninteractive

set -ex

BUILD_PACKAGES="python3-pip python3-wheel python3-dev git patchutils binutils gcc"

apt-get update

# install most of the patroni dependencies from ubuntu packages
apt-cache depends patroni \
        | sed -n -e 's/.* Depends:(python3-.\+\)$/\1/p' \
        | grep -Ev '^python3-(sphinx|etcd|consul|kazoo|kubernetes)' \
        | xargs apt-get install -y ${BUILD_PACKAGES} python3-pystache python3-requests

pip3 install setuptools

if [ "$DEMO" != "true" ]; then
    EXTRAS=",etcd,consul,zookeeper,aws"
    apt-get install -y \
        python3-etcd \
        python3-consul \
        python3-kazoo \
        python3-meld3 \
        python3-boto \
        python3-gevent \
        python3-greenlet \
        python3-cachetools \
        python3-rsa \
        python3-pyasn1-modules \
        python3-swiftclient \
        python3-cffi

    find /usr/share/python-babel-localedata/locale-data -type f ! -name 'en_US*.dat' -delete

    pip3 install filechunkio wal-e[aws,google,swift]==$WALE_VERSION google-crc32c==1.1.2 'protobuf<4.21.0' \
            'git+https://github.com/zalando/pg_view.git@master#egg=pg-view'

    # Non-exclusive backups
    curl -sL https://github.com/CyberDem0n/wal-e/commit/dad4d53969b93c56f1eaa5243ffa8e9051fd7eb7.diff \
            | patch -d /usr/local/lib/python3.6/dist-packages/wal_e -p2
    # WALE_DISABLE_S3_SSE support
    curl -sL https://github.com/CyberDem0n/wal-e/commit/0309317d33d252fcd968b3eb97313a9fdf022c65.diff \
            | patch -d /usr/local/lib/python3.6/dist-packages/wal_e -p2
    curl -sL https://github.com/hughcapet/wal-e/commit/1d94336c14b1f36418963004f35642404d04e250.diff \
            | patch -d /usr/local/lib/python3.6/dist-packages/wal_e -p2
    # Revert https://github.com/wal-e/wal-e/commit/485d834a18c9b0d97115d95f89e16bdc564e9a18, it affects S3 performance
    curl -sL https://github.com/wal-e/wal-e/commit/485d834a18c9b0d97115d95f89e16bdc564e9a18.diff \
            | patch -d /usr/local/lib/python3.6/dist-packages/wal_e -Rp2
    # https://github.com/wal-e/wal-e/issues/318
    sed -i 's/^\(    for i in range(0,\) num_retries):.*/\1 100):/g' /usr/lib/python3/dist-packages/boto/utils.py
fi

pip3 install patroni[kubernetes$EXTRAS]==$PATRONIVERSION

for d in /usr/local/lib/python3.6 /usr/lib/python3; do
    cd $d/dist-packages
    find . -type d -name tests | xargs rm -fr
    find . -type f -name 'test_*.py*' -delete
done
find . -type f -name 'unittest_*.py*' -delete
find . -type f -name '*_test.py' -delete
find . -type f -name '*_test.cpython*.pyc' -delete

# Clean up
apt-get purge -y ${BUILD_PACKAGES}
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/* \
        /var/cache/debconf/* \
        /root/.cache \
        /usr/share/doc \
        /usr/share/man \
        /usr/share/locale/?? \
        /usr/share/locale/??_?? \
        /usr/share/info
find /var/log -type f -exec truncate --size 0 {} \;
