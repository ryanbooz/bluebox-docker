#!/bin/bash
# Docker entrypoint for PostgreSQL development image
# Simplified version based on official postgres entrypoint

set -Eeo pipefail

# Allow the container to be started with `--user`
if [ "$(id -u)" = '0' ]; then
    # Create data directory if needed
    mkdir -p "$PGDATA"
    chown -R postgres:postgres "$PGDATA"
    chmod 700 "$PGDATA"
    
    # Ensure run directory exists
    mkdir -p /var/run/postgresql
    chown -R postgres:postgres /var/run/postgresql
    chmod 2777 /var/run/postgresql
    
    # Restart as postgres user
    exec gosu postgres "$BASH_SOURCE" "$@"
fi

# Initialize database if needed
if [ -z "$(ls -A "$PGDATA")" ]; then
    echo "Initializing PostgreSQL database..."
    
    # Initialize the database
    initdb --username=postgres --pwfile=<(echo "${POSTGRES_PASSWORD:-postgres}") --auth-local=trust --auth-host=scram-sha-256
    
    # Configure pg_hba.conf
    {
        echo "# TYPE  DATABASE        USER            ADDRESS                 METHOD"
        echo "local   all             all                                     trust"
        echo "host    all             all             127.0.0.1/32            scram-sha-256"
        echo "host    all             all             ::1/128                 scram-sha-256"
        echo "host    all             all             0.0.0.0/0               scram-sha-256"
    } > "$PGDATA/pg_hba.conf"
    
    # Configure postgresql.conf
    {
        echo "listen_addresses = '*'"
        echo "shared_preload_libraries = 'pg_stat_statements,pg_cron'"
        echo "cron.database_name = 'postgres'"
    } >> "$PGDATA/postgresql.conf"
    
    # Start postgres temporarily for init scripts
    pg_ctl -D "$PGDATA" -o "-c listen_addresses=''" -w start
    
    # Run init scripts
    for f in /docker-entrypoint-initdb.d/*; do
        case "$f" in
            *.sh)
                echo "Running $f"
                . "$f"
                ;;
            *.sql)
                echo "Running $f"
                psql --username=postgres --no-password --dbname=postgres < "$f"
                ;;
            *.sql.gz)
                echo "Running $f"
                gunzip -c "$f" | psql --username=postgres --no-password --dbname=postgres
                ;;
            *)
                echo "Ignoring $f"
                ;;
        esac
    done
    
    # Stop temporary postgres
    pg_ctl -D "$PGDATA" -m fast -w stop
    
    echo "PostgreSQL initialization complete."
fi

exec "$@"
