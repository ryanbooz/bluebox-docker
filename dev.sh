#!/bin/bash
#
# Manage a long-lived Bluebox dev container
# Uses a separate volume (bluebox-pgdata-dev) that test scripts won't touch.
#

set -e

COMPOSE_CMD="docker-compose -f docker-compose.yaml -f docker-compose.dev.yaml"
CONTAINER_NAME="bluebox-dev"
MAX_WAIT=360  # First init with data loading can take several minutes

wait_for_ready() {
    local waited=0
    echo -n "Waiting for database to be ready "
    while [ $waited -lt $MAX_WAIT ]; do
        status=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "starting")
        case "$status" in
            healthy)
                echo ""
                echo "Database is ready! (${waited}s)"
                return 0
                ;;
            unhealthy)
                echo ""
                echo "Error: Container health check failed. Check logs with: ./dev.sh logs"
                return 1
                ;;
            *)
                echo -n "."
                sleep 3
                waited=$((waited + 3))
                ;;
        esac
    done
    echo ""
    echo "Still initializing after ${MAX_WAIT}s. Check progress with: ./dev.sh logs"
    return 1
}

usage() {
    echo "Usage: ./dev.sh <command>"
    echo ""
    echo "Commands:"
    echo "  up       Start the dev container"
    echo "  down     Stop the dev container (data is kept)"
    echo "  update   Pull latest image and restart (data is kept)"
    echo "  logs     Follow container logs"
    echo "  status   Show container status"
    echo "  psql     Connect with psql as bb_admin"
    echo "  destroy  Remove container AND volume (requires confirmation)"
}

case "${1:-}" in
    up)
        $COMPOSE_CMD up -d
        wait_for_ready
        echo ""
        echo "Connect with: psql -h localhost -p ${PG_PORT:-5432} -U bb_admin -d bluebox"
        ;;
    down)
        $COMPOSE_CMD down
        ;;
    update)
        $COMPOSE_CMD pull
        $COMPOSE_CMD up -d
        wait_for_ready
        echo ""
        echo "Connect with: psql -h localhost -p ${PG_PORT:-5432} -U bb_admin -d bluebox"
        ;;
    logs)
        $COMPOSE_CMD logs -f
        ;;
    status)
        $COMPOSE_CMD ps
        ;;
    psql)
        docker exec -it bluebox-dev psql -U bb_admin -d bluebox
        ;;
    destroy)
        read -p "This will DELETE all dev data. Are you sure? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            $COMPOSE_CMD down -v
            echo "Dev container and volume removed."
        else
            echo "Aborted."
        fi
        ;;
    *)
        usage
        ;;
esac
