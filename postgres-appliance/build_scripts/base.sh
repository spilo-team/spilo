#!/bin/bash

## -------------------------------------------
## Install PostgreSQL, extensions and contribs
## -------------------------------------------

export DEBIAN_FRONTEND=noninteractive 
export MAKEFLAGS="-j $(grep -c ^processor /proc/cpuinfo)" 

POSTGIS_VERSION=3.2
POSTGIS_LEGACY=3.2
BG_MON_COMMIT=271c152412773c70f16bb70cb08597b91adbb947
PG_AUTH_MON_COMMIT=439697fe2980cf48f1760f45e04c2d69b2748e73
PG_MON_COMMIT=0fd850454d5e6812ad7d07ac3c9af9a3dba5abd5
SET_USER=REL3_0_0
PLPROFILER=REL4_1
PAM_OAUTH2=v1.0.1
PLANTUNER_COMMIT=800d81bc85da64ff3ef66e12aed1d4e1e54fc006
PG_PERMISSIONS_COMMIT=314b9359e3d77c0b2ef7dbbde97fa4be80e31925
PG_TM_AUX_COMMIT=5f27c9a56835558f9c6aaf80a2dab81dfa6730b5

set -ex
sed -i 's/^#\s*\(deb.*universe\)$/\1/g' /etc/apt/sources.list

apt-get update

cd /builddeps 
BUILD_PACKAGES="devscripts equivs build-essential fakeroot debhelper git gcc libc6-dev make cmake libevent-dev libbrotli-dev libssl-dev libkrb5-dev"
if [ "$DEMO" = "true" ]; then
    export DEB_PG_SUPPORTED_VERSIONS="$PGVERSION"
    WITH_PERL=false
    rm -f *.deb
    apt-get install -y $BUILD_PACKAGES
else
    BUILD_PACKAGES="$BUILD_PACKAGES zlib1g-dev
                    libprotobuf-c-dev
                    libpam0g-dev
                    libcurl4-openssl-dev
                    libicu-dev python
                    libc-ares-dev
                    pandoc
                    pkg-config"
    apt-get install -y $BUILD_PACKAGES libcurl4

    # install pam_oauth2.so
    git clone -b $PAM_OAUTH2 --recurse-submodules https://github.com/CyberDem0n/pam-oauth2.git
    make -C pam-oauth2 install

    # prepare 3rd sources
    git clone -b $PLPROFILER https://github.com/bigsql/plprofiler.git
    tar -xzf plantuner-${PLANTUNER_COMMIT}.tar.gz
    curl -sL https://github.com/sdudoladov/pg_mon/archive/$PG_MON_COMMIT.tar.gz | tar xz

    for p in python3-keyring python3-docutils ieee-data; do
        version=$(apt-cache show $p | sed -n 's/^Version: //p' | sort -rV | head -n 1)
        echo "Section: misc\nPriority: optional\nStandards-Version: 3.9.8\nPackage: $p\nVersion: $version\nDescription: $p" > $p
        equivs-build $p
    done
fi

if [ "$WITH_PERL" != "true" ]; then
    version=$(apt-cache show perl | sed -n 's/^Version: //p' | sort -rV | head -n 1)
    echo "Section: misc\nPriority: optional\nStandards-Version: 3.9.8\nPackage: perl\nSection:perl\nMulti-Arch: allowed\nReplaces: perl-base\nVersion: $version\nDescription: perl" > perl
    equivs-build perl
fi

if [ "$WITH_PERL" != "true" ] || [ "$DEMO" != "true" ]; then
    dpkg -i *.deb || apt-get -y -f install
fi

curl -sL https://github.com/CyberDem0n/bg_mon/archive/$BG_MON_COMMIT.tar.gz | tar xz
curl -sL https://github.com/sdudoladov/pg_auth_mon/archive/$PG_AUTH_MON_COMMIT.tar.gz | tar xz
curl -sL https://github.com/cybertec-postgresql/pg_permissions/archive/$PG_PERMISSIONS_COMMIT.tar.gz | tar xz
curl -sL https://github.com/hughcapet/pg_tm_aux/archive/$PG_TM_AUX_COMMIT.tar.gz | tar xz
git clone -b $SET_USER https://github.com/pgaudit/set_user.git
git clone https://github.com/timescale/timescaledb.git

apt-get install -y \
    postgresql-common \
    libevent-2.1 \
    libevent-pthreads-2.1 \
    brotli \
    libbrotli1 \
    python3.6 \
    python3-psycopg2

# forbid creation of a main cluster when package is installed
sed -ri 's/#(create_main_cluster) .*$/\1 = false/' /etc/postgresql-common/createcluster.conf

for version in $DEB_PG_SUPPORTED_VERSIONS; do
    sed -i "s/ main.*$/ main $version/g" /etc/apt/sources.list.d/pgdg.list
    apt-get update

    if [ "$DEMO" != "true" ]; then
        EXTRAS="postgresql-pltcl-${version}
                postgresql-${version}-dirtyread
                postgresql-${version}-extra-window-functions
                postgresql-${version}-first-last-agg
                postgresql-${version}-hypopg
                postgresql-${version}-plproxy"

        if [ $version != "15" ]; then
            # not yet adapted for pg15
            EXTRAS="$EXTRAS
                postgresql-${version}-pgaudit
                postgresql-${version}-repack
                postgresql-${version}-wal2json
                postgresql-${version}-hll
                postgresql-${version}-pg-checksums
                postgresql-${version}-pgl-ddl-deploy
                postgresql-${version}-pglogical
                postgresql-${version}-pglogical-ticker
                postgresql-${version}-pgq-node
                postgresql-${version}-pldebugger
                postgresql-${version}-pllua
                postgresql-${version}-plpgsql-check
                postgresql-${version}-postgis-${POSTGIS_VERSION%.*}
                postgresql-${version}-postgis-${POSTGIS_VERSION%.*}-scripts"
        fi

        if [ "$WITH_PERL" = "true" ]; then
            EXTRAS="$EXTRAS postgresql-plperl-${version}"
        fi

        if [ ${version%.*} -ge 10 ] && [ ${version%.*} -lt 15 ]; then
            EXTRAS="$EXTRAS postgresql-${version}-decoderbufs"
        fi

        if [ ${version%.*} -lt 11 ]; then
            EXTRAS="$EXTRAS postgresql-${version}-amcheck"
        fi
        #those that have patches
        MISSING_EXTRAS="pgaudit repack wal2json decoderbufs"
    fi

    # Install PostgreSQL binaries, contrib, plproxy and multiple pl's
    apt-get install --allow-downgrades -y \
        postgresql-contrib-${version} \
        postgresql-plpython3-${version} \
        postgresql-server-dev-${version} \
        postgresql-${version}-pgq3 \
        postgresql-${version}-pg-stat-kcache \
        $EXTRAS

    if [ $version != "15" ]; then
        apt-get install -y postgresql-${version}-cron
    else
        MISSING="cron"
    fi

    # Install 3rd party stuff
    cd timescaledb
    for v in $TIMESCALEDB; do
        git checkout $v
        sed -i "s/VERSION 3.11/VERSION 3.10/" CMakeLists.txt
        if BUILD_FORCE_REMOVE=true ./bootstrap -DREGRESS_CHECKS=OFF -DWARNINGS_AS_ERRORS=OFF \
                -DTAP_CHECKS=OFF -DPG_CONFIG=/usr/lib/postgresql/$version/bin/pg_config \
                -DAPACHE_ONLY=$TIMESCALEDB_APACHE_ONLY -DSEND_TELEMETRY_DEFAULT=NO; then
            make -C build install
            strip /usr/lib/postgresql/$version/lib/timescaledb*.so
        fi
        git reset --hard
        git clean -f -d
    done

    cd ..

    if [ "$DEMO" != "true" ]; then
        EXTRA_EXTENSIONS="plantuner-${PLANTUNER_COMMIT} plprofiler"
        if [ ${version%.*} -ge 10 ]; then
            EXTRA_EXTENSIONS="$EXTRA_EXTENSIONS pg_mon-${PG_MON_COMMIT}"
        fi
    else
        EXTRA_EXTENSIONS=""
    fi

    for n in bg_mon-${BG_MON_COMMIT} \
            pg_auth_mon-${PG_AUTH_MON_COMMIT} \
            set_user \
            pg_permissions-${PG_PERMISSIONS_COMMIT} \
            pg_tm_aux-${PG_TM_AUX_COMMIT} \
            $EXTRA_EXTENSIONS; do
        make -C $n USE_PGXS=1 clean install-strip
    done
done

apt-get install -y skytools3-ticker pgbouncer

sed -i "s/ main.*$/ main/g" /etc/apt/sources.list.d/pgdg.list
apt-get update
apt-get install -y postgresql postgresql-server-dev-all postgresql-all libpq-dev
for version in $DEB_PG_SUPPORTED_VERSIONS; do
    apt-get install -y postgresql-server-dev-${version}
done

if [ "$DEMO" != "true" ]; then
    for version in $DEB_PG_SUPPORTED_VERSIONS; do
        # due to dependency issues partman has to be installed separately
        if [ $version != "15" ]; then
            apt-get install -y postgresql-${version}-partman
        else
            MISSING_EXTRAS="$MISSING_EXTRAS partman"
        fi
        # create postgis symlinks to make it possible to perform update
        ln -s postgis-${POSTGIS_VERSION%.*}.so /usr/lib/postgresql/${version}/lib/postgis-2.5.so
    done
fi

    # build and install missing packages
for pkg in pgextwlist $MISSING $MISSING_EXTRAS; do
    apt-get source postgresql-14-${pkg}
    cd $(ls -d *${pkg%?}*-*/)
    if [ -f ../$pkg.patch ]; then patch -p1 < ../$pkg.patch; fi
    if [ "$pkg" = "pgextwlist" ]; then
        sed -i '/postgresql-all/d' debian/control.in
        # make it possible to use it from shared_preload_libraries
        perl -ne 'print unless /PG_TRY/ .. /PG_CATCH/' pgextwlist.c > pgextwlist.c.f
        egrep -v '(PG_END_TRY|EmitWarningsOnPlaceholders)' pgextwlist.c.f > pgextwlist.c
    fi
    if [ "$pkg" = "pgaudit" ]; then
            echo "15" > debian/pgversions
        fi
    pg_buildext updatecontrol
    if [ "$pkg" = "pgextwlist" ]; then
            DEB_BUILD_OPTIONS=nocheck debuild -b -uc -us
        else
            DEB_BUILD_OPTIONS=nocheck DEB_PG_SUPPORTED_VERSIONS=$PGVERSION debuild -b -uc -us
        fi
    cd ..
    for version in $DEB_PG_SUPPORTED_VERSIONS; do
        for deb in postgresql-${version}-${pkg}_*.deb; do
            if [ -f $deb ]; then dpkg -i $deb; fi
        done
    done
done

# make it possible for cron to work without root
gcc -s -shared -fPIC -o /usr/local/lib/cron_unprivileged.so cron_unprivileged.c

# Remove unnecessary packages
apt-get purge -y ${BUILD_PACKAGES} postgresql postgresql-all postgresql-server-dev-* libpq-dev=* libmagic1 bsdmainutils
apt-get autoremove -y
apt-get clean
dpkg -l | grep '^rc' | awk '{print $2}' | xargs apt-get purge -y

# Try to minimize size by creating symlinks instead of duplicate files
if [ "$DEMO" != "true" ]; then
    cd /usr/lib/postgresql/$PGVERSION/bin
    for u in clusterdb \
            pg_archivecleanup \
            pg_basebackup \
            pg_isready \
            pg_recvlogical \
            pg_test_fsync \
            pg_test_timing \
            pgbench \
            reindexdb \
            vacuumlo *.py; do
        for v in /usr/lib/postgresql/*; do
            if [ "$v" != "/usr/lib/postgresql/$PGVERSION" ] && [ -f "$v/bin/$u" ]; then
                rm $v/bin/$u
                ln -s ../../$PGVERSION/bin/$u $v/bin/$u
            fi;
        done;
    done

    set +x

    for v1 in $(ls -1d /usr/share/postgresql/* | sort -Vr); do
        # relink files with the same content
        cd $v1/extension
        for orig in $(ls -1 *.sql | grep -v -- '--'); do
            for f in ${orig%.sql}--*.sql; do
                if [ ! -L $f ] && diff $orig $f > /dev/null; then
                    echo "creating symlink $f -> $orig"
                    rm $f && ln -s $orig $f
                fi
            done
        done

        for e in pgq pgq_node plproxy address_standardizer address_standardizer_data_us; do
            orig=$(basename "$(find -maxdepth 1 -type f -name "$e--*--*.sql" | head -n1)")
            if [ "x$orig" != "x" ]; then
                for f in $e--*--*.sql; do
                    if [ "$f" != "$orig" ] && [ ! -L $f ] && diff $f $orig > /dev/null; then
                        echo "creating symlink $f -> $orig"
                        rm $f && ln -s $orig $f
                    fi
                done
            fi
        done

        # relink files with the same name and content across different major versions
        started=0
        for v2 in $(ls -1d /usr/share/postgresql/* | sort -Vr); do
            if [ "${v2##*/}" = "15" ]; then
                continue
            fi
            if [ $v1 = $v2 ]; then
                started=1
            elif [ $started = 1 ]; then
                for d1 in extension contrib contrib/postgis-$POSTGIS_VERSION; do
                    cd $v1/$d1
                    d2="$d1"
                    d1="../../${v1##*/}/$d1"
                    if [ "${d2%-*}" = "contrib/postgis" ]; then
                        if [ "${v2##*/}" = "9.6" ]; then d2="${d2%-*}-$POSTGIS_LEGACY"; fi
                        d1="../$d1"
                    fi
                    d2="$v2/$d2"
                    for f in *.html *.sql *.control *.pl; do
                        if [ -f $d2/$f ] && [ ! -L $d2/$f ] && diff $d2/$f $f > /dev/null; then
                            echo "creating symlink $d2/$f -> $d1/$f"
                            rm $d2/$f && ln -s $d1/$f $d2/$f
                        fi
                    done
                done
            fi
        done
    done
    set -x
fi

# Clean up
rm -rf /var/lib/apt/lists/* \
        /var/cache/debconf/* \
        /builddeps \
        /usr/share/doc \
        /usr/share/man \
        /usr/share/info \
        /usr/share/locale/?? \
        /usr/share/locale/??_?? \
        /usr/share/postgresql/*/man \
        /etc/pgbouncer/* \
        /usr/lib/postgresql/*/bin/createdb \
        /usr/lib/postgresql/*/bin/createlang \
        /usr/lib/postgresql/*/bin/createuser \
        /usr/lib/postgresql/*/bin/dropdb \
        /usr/lib/postgresql/*/bin/droplang \
        /usr/lib/postgresql/*/bin/dropuser \
        /usr/lib/postgresql/*/bin/pg_standby \
        /usr/lib/postgresql/*/bin/pltcl_*
find /var/log -type f -exec truncate --size 0 {} \;
