#!/bin/bash
#
# Start a Bluebox Postgres container
#

set -e

# Defaults
DEFAULT_PG_VERSION="18"
DEFAULT_PORT="5432"

echo "========================================"
echo "Bluebox Postgres Container Setup"
echo "========================================"
echo

# Prompt for Postgres version
echo "Available versions: 14, 15, 16, 17, 18, 19-dev"
read -p "Postgres version [${DEFAULT_PG_VERSION}]: " PG_VERSION
PG_VERSION=${PG_VERSION:-$DEFAULT_PG_VERSION}

# Validate version
if [[ ! "$PG_VERSION" =~ ^(14|15|16|17|18|19-dev)$ ]]; then
    echo "Error: Unsupported Postgres version. Choose 14, 15, 16, 17, 18, or 19-dev."
    exit 1
fi

# Check if default port is in use and find an available one
check_port() {
    if command -v lsof &> /dev/null; then
        lsof -iTCP:"$1" -sTCP:LISTEN &> /dev/null && return 1 || return 0
    elif command -v ss &> /dev/null; then
        ss -tuln | grep -q ":$1 " && return 1 || return 0
    elif command -v netstat &> /dev/null; then
        netstat -tuln | grep -q ":$1 " && return 1 || return 0
    else
        # Can't check, assume available
        return 0
    fi
}

SUGGESTED_PORT="$DEFAULT_PORT"
if ! check_port "$DEFAULT_PORT"; then
    echo "Note: Port $DEFAULT_PORT is already in use."
    for PORT_CANDIDATE in 5433 5434 5435 5436 5437 5438; do
        if check_port "$PORT_CANDIDATE"; then
            SUGGESTED_PORT="$PORT_CANDIDATE"
            break
        fi
    done
fi

read -p "Host port [${SUGGESTED_PORT}]: " PG_PORT
PG_PORT=${PG_PORT:-$SUGGESTED_PORT}

# Validate port
if [[ ! "$PG_PORT" =~ ^[0-9]+$ ]] || [ "$PG_PORT" -lt 1024 ] || [ "$PG_PORT" -gt 65535 ]; then
    echo "Error: Port must be a number between 1024 and 65535."
    exit 1
fi

# Set project name based on version
PROJECT_NAME="bluebox-pg${PG_VERSION}"

echo
echo "----------------------------------------"
echo "Configuration:"
echo "  Postgres version: ${PG_VERSION}"
echo "  Host port:        ${PG_PORT}"
echo "  Project name:     ${PROJECT_NAME}"
echo "----------------------------------------"
echo

# Check if this project is already running
if docker compose -p "$PROJECT_NAME" ps --status running 2>/dev/null | grep -q "bluebox"; then
    echo "Warning: ${PROJECT_NAME} appears to already be running."
    read -p "Stop and recreate it? [y/N]: " RECREATE
    if [[ ! "$RECREATE" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    docker compose -p "$PROJECT_NAME" down
fi

# Wait for container to be healthy (init scripts complete + postgres accepting connections)
wait_for_ready() {
    local container="$1"
    local max_wait=360
    local waited=0
    local seen_scripts=""

    echo "Waiting for database to be ready..."
    while [ $waited -lt $max_wait ]; do
        status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "starting")

        # Show init script progress from container logs
        for script in $(docker logs "$container" 2>&1 \
            | grep -o '[a-z]*ing /docker-entrypoint-initdb.d/[^ ]*' \
            | sed 's|.*/docker-entrypoint-initdb.d/||' \
            || true); do
            case "$seen_scripts" in
                *"|${script}|"*) ;;  # already shown
                *)
                    seen_scripts="${seen_scripts}|${script}|"
                    echo "  → Running ${script}"
                    ;;
            esac
        done

        case "$status" in
            healthy)
                echo ""
                echo "Database is ready! (${waited}s)"
                return 0
                ;;
            unhealthy)
                echo ""
                echo "Error: Container health check failed. Check logs:"
                echo "  docker compose -p ${PROJECT_NAME} logs -f"
                return 1
                ;;
            *)
                sleep 3
                waited=$((waited + 3))
                ;;
        esac
    done
    echo ""
    echo "Still initializing after ${max_wait}s. Check progress:"
    echo "  docker compose -p ${PROJECT_NAME} logs -f"
    return 1
}

# Pull latest image and start the container
echo "Checking for image updates..."
PG_VERSION="$PG_VERSION" docker compose -p "$PROJECT_NAME" pull

echo "Starting ${PROJECT_NAME}..."
PG_VERSION="$PG_VERSION" PG_PORT="$PG_PORT" docker compose -p "$PROJECT_NAME" up -d

CONTAINER_NAME="bluebox-${PG_VERSION}"
wait_for_ready "$CONTAINER_NAME"

echo
echo "========================================"
echo "Container is ready!"
echo "========================================"
echo
echo "Connect with:"
echo "  psql -h localhost -p ${PG_PORT} -U bb_admin -d bluebox"
echo
echo "Stop with:"
echo "  docker compose -p ${PROJECT_NAME} down"
echo
echo "View logs:"
echo "  docker compose -p ${PROJECT_NAME} logs -f"
echo
