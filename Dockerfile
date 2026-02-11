# Bluebox PostgreSQL Image
# A sample database for learning PostgreSQL with realistic, continuously-updating data
#
# Based on postgres-ai/custom-images patterns
# https://github.com/ryanbooz/bluebox-docker

ARG PG_SERVER_VERSION=18
ARG POSTGIS_MAJOR_VERSION=3

FROM postgres:${PG_SERVER_VERSION}-bookworm
LABEL maintainer="Ryan Booz <ryan@softwareandbooz.com>"
LABEL org.opencontainers.image.source="https://github.com/ryanbooz/bluebox-docker"
LABEL org.opencontainers.image.description="Bluebox sample database - PostgreSQL with realistic rental data"

ARG PG_SERVER_VERSION
ENV PG_SERVER_VERSION=${PG_SERVER_VERSION:-18}

ARG POSTGIS_MAJOR_VERSION
ENV POSTGIS_MAJOR_VERSION=${POSTGIS_MAJOR_VERSION:-3}

ARG PG_UNIX_SOCKET_DIR
ENV PG_UNIX_SOCKET_DIR=${PG_UNIX_SOCKET_DIR:-"/var/run/postgresql"}

ARG PG_SERVER_PORT
ENV PG_SERVER_PORT=${PG_SERVER_PORT:-5432}

ARG LOGERRORS_VERSION
ENV LOGERRORS_VERSION=${LOGERRORS_VERSION:-2.1.3}

ARG PGVECTOR_VERSION
ENV PGVECTOR_VERSION=${PGVECTOR_VERSION:-0.8.1}

ARG PG_CRON_VERSION
ENV PG_CRON_VERSION=${PG_CRON_VERSION:-1.4.2}

RUN apt-get clean && rm -rf /var/lib/apt/lists/partial \
    && PG_SERVER_VERSION="$( echo ${PG_SERVER_VERSION} | sed 's/beta.*//' | sed 's/rc.*//' )" \
    && apt-get update -o Acquire::CompressionTypes::Order::=gz \
    && apt-get install --no-install-recommends -y wget make gcc unzip sudo git \
       curl libc6-dev apt-transport-https ca-certificates pgxnclient bc \
       build-essential libssl-dev krb5-multidev libkrb5-dev lsb-release apt-utils flex \
    && apt-get install --no-install-recommends -y postgresql-server-dev-${PG_SERVER_VERSION} \
    # plpython3
    && apt-get install --no-install-recommends -y postgresql-plpython3-${PG_SERVER_VERSION} \
    # postgis
    && apt-get install -y --no-install-recommends \
           ca-certificates \
           postgresql-"${PG_SERVER_VERSION}"-postgis-"${POSTGIS_MAJOR_VERSION}" \
           postgresql-"${PG_SERVER_VERSION}"-postgis-"${POSTGIS_MAJOR_VERSION}"-scripts \
    # pg_repack
    && apt-get install --no-install-recommends -y postgresql-${PG_SERVER_VERSION}-repack \
    # hypopg
    && apt-get install --no-install-recommends -y \
       postgresql-${PG_SERVER_VERSION}-hypopg \
       postgresql-${PG_SERVER_VERSION}-hypopg-dbgsym \
    # pgaudit
    && apt-get install --no-install-recommends -y postgresql-${PG_SERVER_VERSION}-pgaudit \
    # pg_hint_plan
    && if [ $(echo "$PG_SERVER_VERSION > 11" | /usr/bin/bc) = "1" ] && [ $(echo "$PG_SERVER_VERSION < 17" | /usr/bin/bc) = "1" ]; then \
         apt-get install --no-install-recommends -y postgresql-${PG_SERVER_VERSION}-pg-hint-plan; \
       else \
         export PG_PLAN_HINT_VERSION=$(echo $PG_SERVER_VERSION | sed 's/\.//') \
         && wget --quiet -O /tmp/pg_hint_plan.zip https://github.com/ossc-db/pg_hint_plan/archive/PG${PG_PLAN_HINT_VERSION}.zip \
         && unzip /tmp/pg_hint_plan.zip -d /tmp \
         && cd /tmp/pg_hint_plan-PG${PG_PLAN_HINT_VERSION} \
         && make && make install; \
      fi \
    # timescaledb
    && if [ $(echo "$PG_SERVER_VERSION > 11" | /usr/bin/bc) = "1" ]; then \
         echo "deb https://packagecloud.io/timescale/timescaledb/debian/ $(lsb_release -c -s) main" > /etc/apt/sources.list.d/timescaledb.list \
           && wget --quiet -O - https://packagecloud.io/timescale/timescaledb/gpgkey | sudo apt-key add - \
           && apt-get update \
           && apt-get install --no-install-recommends -y \
              timescaledb-2-postgresql-${PG_SERVER_VERSION}; \
       fi \
    # hll extension
    && apt-get install --no-install-recommends -y postgresql-"${PG_SERVER_VERSION}"-hll \
    # pg_cron extension
    && if [ $(echo "$PG_SERVER_VERSION >= 10" | /usr/bin/bc) = "1" ] && [ $(echo "$PG_SERVER_VERSION < 16" | /usr/bin/bc) = "1" ]; then \
         cd /tmp && git clone --branch v${PG_CRON_VERSION} --single-branch https://github.com/citusdata/pg_cron.git \
         && cd pg_cron \
         && make && make install; \
       elif [ $(echo "$PG_SERVER_VERSION >= 16" | /usr/bin/bc) = "1" ]; then \
         apt-get install --no-install-recommends -y postgresql-${PG_SERVER_VERSION}-cron; \
       fi \
    # postgresql_anonymizer
    && pgxn install ddlx && pgxn install postgresql_anonymizer \
    # pgvector
    && if [ $(echo "$PG_SERVER_VERSION >= 11" | /usr/bin/bc) = "1" ]; then \
        if [ "${PG_SERVER_VERSION}" = "11" ]; then PGVECTOR_VERSION="0.5.1"; \
        elif [ "${PG_SERVER_VERSION}" = "12" ]; then PGVECTOR_VERSION="0.7.4"; \
        else PGVECTOR_VERSION="${PGVECTOR_VERSION}"; \
        fi \
        && cd /tmp && git clone --branch v${PGVECTOR_VERSION} https://github.com/pgvector/pgvector.git \
        && cd pgvector && make OPTFLAGS="" install \
        && mkdir /usr/share/doc/pgvector \
        && cp LICENSE README.md /usr/share/doc/pgvector \
        && cp sql/vector.sql /usr/share/postgresql/${PG_SERVER_VERSION}/extension/vector--${PGVECTOR_VERSION}.sql; \
    fi \
    # pgBackRest
    && apt-get install --no-install-recommends -y \
       pgbackrest zstd openssh-client \
       && mkdir -p -m 700 /var/lib/postgresql/.ssh \
       && chown postgres:postgres /var/lib/postgresql/.ssh \
    # Cleanup
    && cd / && rm -rf /tmp/* && apt-get purge -y --auto-remove \
       gcc make wget unzip curl libc6-dev apt-transport-https git \
       postgresql-server-dev-${PG_SERVER_VERSION} pgxnclient build-essential \
       libssl-dev krb5-multidev comerr-dev krb5-multidev libkrb5-dev apt-utils lsb-release \
       libgssrpc4 \
    && apt-get clean -y autoclean \
    && rm -rf /var/lib/apt/lists/*

# Configure PostgreSQL defaults
RUN echo "shared_preload_libraries='pg_stat_statements,auto_explain,pg_cron'" >> /usr/share/postgresql/postgresql.conf.sample \
    && echo "cron.database_name='postgres'" >> /usr/share/postgresql/postgresql.conf.sample \
    && echo "max_wal_size='2GB'" >> /usr/share/postgresql/postgresql.conf.sample \
    && echo "min_wal_size='512MB'" >> /usr/share/postgresql/postgresql.conf.sample \
    && echo "checkpoint_timeout='15min'" >> /usr/share/postgresql/postgresql.conf.sample \
    && echo "checkpoint_completion_target=0.9" >> /usr/share/postgresql/postgresql.conf.sample

# Copy init scripts
COPY init/ /docker-entrypoint-initdb.d/

EXPOSE ${PG_SERVER_PORT}
