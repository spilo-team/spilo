ARG BASE_IMAGE=ubuntu:18.04
ARG PGVERSION=15
ARG TIMESCALEDB="1.7.5 2.3.1 2.7.0"
ARG DEMO=false
ARG COMPRESS=false

FROM $BASE_IMAGE as dependencies-builder

COPY dependencies/debs /builddeps/
COPY build_scripts/walg.sh /builddeps/

RUN bash /builddeps/walg.sh

FROM $BASE_IMAGE as builder-false

ARG DEMO
ARG ADDITIONAL_LOCALES=

COPY build_scripts/prepare.sh /builddeps/

RUN bash /builddeps/prepare.sh

COPY cron_unprivileged.c dependencies/src /builddeps/
COPY patches/*.patch /builddeps/
COPY build_scripts/base.sh /builddeps/
COPY --from=dependencies-builder /builddeps/*.deb /builddeps/

ARG PGVERSION
ARG TIMESCALEDB
ARG TIMESCALEDB_APACHE_ONLY=true
ARG DEMO
ARG COMPRESS
ARG PGOLDVERSIONS="10 11 12 13 14"
ARG WITH_PERL=false

ARG DEB_PG_SUPPORTED_VERSIONS="$PGOLDVERSIONS $PGVERSION"

# Install PostgreSQL, extensions and contribs
RUN bash /builddeps/base.sh

# Install wal-g
COPY --from=dependencies-builder /builddeps/wal-g /usr/local/bin/
COPY build_scripts/patroni_wale.sh build_scripts/compress_build.sh /builddeps/

# Install patroni and wal-e
RUN bash /builddeps/patroni_wale.sh

RUN if [ "$COMPRESS" = "true" ]; then bash builddeps/compress_build.sh; fi


FROM scratch as builder-true
COPY --from=builder-false / /


FROM builder-${COMPRESS}

LABEL maintainer="Alexander Kukushkin <alexander.kukushkin@zalando.de>"

ARG PGVERSION
ARG TIMESCALEDB
ARG DEMO
ARG COMPRESS

EXPOSE 5432 8008 8080

ENV LC_ALL=en_US.utf-8 \
    PATH=$PATH:/usr/lib/postgresql/$PGVERSION/bin \
    PGHOME=/home/postgres \
    RW_DIR=/run \
    TIMESCALEDB=$TIMESCALEDB \
    DEMO=$DEMO

ENV WALE_ENV_DIR=$RW_DIR/etc/wal-e.d/env \
    LOG_ENV_DIR=$RW_DIR/etc/log.d/env \
    PGROOT=$PGHOME/pgdata/pgroot

ENV PGDATA=$PGROOT/data \
    PGLOG=$PGROOT/pg_log

WORKDIR $PGHOME

COPY motd /etc/
COPY runit /etc/service/
COPY pgq_ticker.ini $PGHOME/
COPY build_scripts/post_build.sh /builddeps/

RUN  bash /builddeps/post_build.sh && rm -rf /builddeps/

COPY scripts bootstrap major_upgrade /scripts/
COPY launch.sh /

CMD ["/bin/sh", "/launch.sh", "init"]
