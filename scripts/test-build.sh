#!/bin/bash
# Test script for Bluebox Docker image
# Builds the image, starts the container, verifies data loaded correctly

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PG_VERSION=${PG_VERSION:-18}
CONTAINER_NAME="bluebox-${PG_VERSION}"
MAX_WAIT=60  # Maximum seconds to wait for container to be ready

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

cleanup() {
    log_info "Cleaning up test environment..."
    docker-compose down -v > /dev/null 2>&1 || true
    log_success "Cleanup complete"
}

# Trap errors and cleanup
trap 'log_error "Test failed! Cleaning up..."; cleanup; exit 1' ERR

# Main test flow
echo ""
log_info "=== Bluebox Docker Build Test ==="
log_info "PostgreSQL Version: ${PG_VERSION}"
echo ""

# Step 1: Clean up any existing containers
log_info "Step 1: Cleaning up existing containers..."
docker-compose down -v > /dev/null 2>&1 || true
log_success "Cleanup complete"
echo ""

# Step 2: Build the Docker image
log_info "Step 2: Building Docker image (bluebox-${PG_VERSION}:latest)..."
log_info "This may take several minutes on first build..."
log_info "Installing PostgreSQL ${PG_VERSION} and extensions..."

docker build \
    --build-arg PG_SERVER_VERSION=${PG_VERSION} \
    -t bluebox-${PG_VERSION}:latest \
    . 2>&1 | tee /tmp/bluebox-build.log

# Check if build actually succeeded by exit code, not by grepping for "error"
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    log_error "Build failed! Check /tmp/bluebox-build.log for details"
    exit 1
fi

# Check if build actually succeeded
if ! docker image inspect bluebox-${PG_VERSION}:latest > /dev/null 2>&1; then
    log_error "Build failed - image not found!"
    exit 1
fi

log_success "Image built successfully: bluebox-${PG_VERSION}:latest"
echo ""

# Step 3: Start the container
log_info "Step 3: Starting container..."
docker-compose up -d
log_success "Container started"
echo ""

# Step 4: Wait for PostgreSQL to be ready
log_info "Step 4: Waiting for PostgreSQL to initialize..."
SECONDS_WAITED=0
while [ $SECONDS_WAITED -lt $MAX_WAIT ]; do
    if docker exec ${CONTAINER_NAME} pg_isready -U postgres -d bluebox > /dev/null 2>&1; then
        log_success "PostgreSQL is ready (took ${SECONDS_WAITED}s)"
        break
    fi
    echo -n "."
    sleep 2
    SECONDS_WAITED=$((SECONDS_WAITED + 2))
done

if [ $SECONDS_WAITED -ge $MAX_WAIT ]; then
    log_error "PostgreSQL failed to start within ${MAX_WAIT} seconds"
    docker-compose logs --tail=50
    exit 1
fi
echo ""

# Step 5: Wait for initialization and check CSV loading
log_info "Step 5: Waiting for data initialization to complete..."
MAX_INIT_WAIT=90
INIT_SECONDS_WAITED=0
RENTAL_LOG=""
PAYMENT_LOG=""

while [ $INIT_SECONDS_WAITED -lt $MAX_INIT_WAIT ]; do
    # Check for both CSV load messages
    RENTAL_LOG=$(docker-compose logs 2>&1 | grep "Loaded .* rental records from CSV" || echo "")
    PAYMENT_LOG=$(docker-compose logs 2>&1 | grep "Loaded .* payment records from CSV" || echo "")

    # If both found, we're done!
    if [ -n "$RENTAL_LOG" ] && [ -n "$PAYMENT_LOG" ]; then
        log_success "Initialization complete (took ${INIT_SECONDS_WAITED}s)"
        break
    fi

    echo -n "."
    sleep 3
    INIT_SECONDS_WAITED=$((INIT_SECONDS_WAITED + 3))
done

echo ""

# Verify we found both messages
if [ -z "$RENTAL_LOG" ]; then
    log_error "Rental CSV load message not found after ${MAX_INIT_WAIT} seconds"
    log_warning "Recent logs:"
    docker-compose logs --tail=30
    exit 1
fi

if [ -z "$PAYMENT_LOG" ]; then
    log_error "Payment CSV load message not found after ${MAX_INIT_WAIT} seconds"
    log_warning "Recent logs:"
    docker-compose logs --tail=30
    exit 1
fi

# Extract and display counts
RENTAL_COUNT=$(echo "$RENTAL_LOG" | grep -oE '[0-9]+' | head -1)
PAYMENT_COUNT=$(echo "$PAYMENT_LOG" | grep -oE '[0-9]+' | head -1)
log_success "Rental data loaded: ${RENTAL_COUNT} records"
log_success "Payment data loaded: ${PAYMENT_COUNT} records"
echo ""

# Step 6: Verify data in database
log_info "Step 6: Verifying data in database..."

# Check rental count
DB_RENTAL_COUNT=$(docker exec ${CONTAINER_NAME} psql -U bb_admin -d bluebox -tAc "SELECT count(*) FROM bluebox.rental;" 2>/dev/null || echo "0")
if [ "$DB_RENTAL_COUNT" -gt 0 ]; then
    log_success "Rental table contains ${DB_RENTAL_COUNT} records"
else
    log_error "Rental table is empty or query failed"
    exit 1
fi

# Check payment count
DB_PAYMENT_COUNT=$(docker exec ${CONTAINER_NAME} psql -U bb_admin -d bluebox -tAc "SELECT count(*) FROM bluebox.payment;" 2>/dev/null || echo "0")
if [ "$DB_PAYMENT_COUNT" -gt 0 ]; then
    log_success "Payment table contains ${DB_PAYMENT_COUNT} records"
else
    log_error "Payment table is empty or query failed"
    exit 1
fi

# Check foreign key integrity
FK_CHECK=$(docker exec ${CONTAINER_NAME} psql -U bb_admin -d bluebox -tAc "
    SELECT count(*)
    FROM bluebox.payment p
    JOIN bluebox.rental r ON p.rental_id = r.rental_id;
" 2>/dev/null || echo "0")

if [ "$FK_CHECK" = "$DB_PAYMENT_COUNT" ]; then
    log_success "Foreign key relationships valid (all ${FK_CHECK} payments link to rentals)"
else
    log_error "Foreign key integrity issue: ${FK_CHECK} valid links vs ${DB_PAYMENT_COUNT} payments"
    exit 1
fi
echo ""

# Step 7: Additional checks
log_info "Step 7: Running additional checks..."

# Check that other tables have data too
CUSTOMER_COUNT=$(docker exec ${CONTAINER_NAME} psql -U bb_admin -d bluebox -tAc "SELECT count(*) FROM bluebox.customer;" 2>/dev/null || echo "0")
FILM_COUNT=$(docker exec ${CONTAINER_NAME} psql -U bb_admin -d bluebox -tAc "SELECT count(*) FROM bluebox.film;" 2>/dev/null || echo "0")

if [ "$CUSTOMER_COUNT" -gt 0 ] && [ "$FILM_COUNT" -gt 0 ]; then
    log_success "Reference data loaded: ${CUSTOMER_COUNT} customers, ${FILM_COUNT} films"
else
    log_error "Reference data missing"
    exit 1
fi

# Check pg_cron jobs are set up
CRON_JOBS=$(docker exec ${CONTAINER_NAME} psql -U postgres -d postgres -tAc "SELECT count(*) FROM cron.job;" 2>/dev/null || echo "0")
if [ "$CRON_JOBS" -gt 0 ]; then
    log_success "pg_cron configured: ${CRON_JOBS} jobs scheduled"
else
    log_warning "pg_cron jobs not found (may not be an error if jobs haven't been set up yet)"
fi
echo ""

# Summary
echo ""
log_success "=== Test Summary ==="
echo -e "  PostgreSQL Version: ${GREEN}${PG_VERSION}${NC}"
echo -e "  Container Name:     ${GREEN}${CONTAINER_NAME}${NC}"
echo -e "  Rentals Loaded:     ${GREEN}${DB_RENTAL_COUNT}${NC}"
echo -e "  Payments Loaded:    ${GREEN}${DB_PAYMENT_COUNT}${NC}"
echo -e "  Customers:          ${GREEN}${CUSTOMER_COUNT}${NC}"
echo -e "  Films:              ${GREEN}${FILM_COUNT}${NC}"
echo -e "  Status:             ${GREEN}PASSED ✓${NC}"
echo ""

# Ask about cleanup
read -p "Keep container running for manual testing? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    cleanup
    log_info "Container stopped and removed"
else
    log_info "Container still running. Connect with:"
    echo -e "  ${BLUE}docker exec -it ${CONTAINER_NAME} psql -U bb_admin -d bluebox${NC}"
    echo ""
    log_info "To stop later:"
    echo -e "  ${BLUE}docker-compose down -v${NC}"
fi

echo ""
log_success "Test completed successfully!"
exit 0