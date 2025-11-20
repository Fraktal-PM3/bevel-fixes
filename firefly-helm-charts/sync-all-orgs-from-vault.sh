#!/bin/bash
##############################################################################################
#  Copyright Accenture. All Rights Reserved.
#
#  SPDX-License-Identifier: Apache-2.0
##############################################################################################

set -e

# Configuration
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-mydevroot}"
VAULT_SECRET_PATH="${VAULT_SECRET_PATH:-secretsv2}"
NAMESPACE="${NAMESPACE:-default}"
NETWORK_TYPE="${NETWORK_TYPE:-}"

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

usage() {
    cat <<EOF
Usage: $0 <org1> [org2] [org3] ...

Sync admin MSP credentials for multiple organizations from Vault to Kubernetes.

Arguments:
  org1, org2, ...     Organization names to sync

Environment Variables:
  VAULT_ADDR          Vault server address (default: http://localhost:8200)
  VAULT_TOKEN         Vault authentication token (default: mydevroot)
  VAULT_SECRET_PATH   Vault KV path (default: secretsv2)
  NAMESPACE           Kubernetes namespace (default: default)
  NETWORK_TYPE        Network type prefix (e.g., 'fabric-', optional)

Examples:
  # Sync multiple organizations
  $0 org1 org2 org3

  # With network type
  NETWORK_TYPE=fabric- $0 manufacturer carrier warehouse

  # Different namespace
  NAMESPACE=production $0 org1 org2

EOF
    exit 1
}

if [ $# -eq 0 ]; then
    echo "Error: At least one organization name is required"
    usage
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/sync-msp-from-vault.sh"

if [ ! -f "$SYNC_SCRIPT" ]; then
    log_warn "sync-msp-from-vault.sh not found in same directory"
    exit 1
fi

echo "=========================================="
echo "Bulk MSP Sync from Vault"
echo "=========================================="
echo "Organizations: $@"
echo "Namespace: $NAMESPACE"
echo "Vault: $VAULT_ADDR"
echo "=========================================="
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0
FAILED_ORGS=()

for ORG in "$@"; do
    echo ""
    log_info "Processing organization: $ORG"
    echo "----------------------------------------"

    SECRET_NAME="${ORG}-msp"

    if VAULT_ADDR="$VAULT_ADDR" \
       VAULT_TOKEN="$VAULT_TOKEN" \
       VAULT_SECRET_PATH="$VAULT_SECRET_PATH" \
       NAMESPACE="$NAMESPACE" \
       NETWORK_TYPE="$NETWORK_TYPE" \
       "$SYNC_SCRIPT" "$ORG" "$SECRET_NAME"; then

        ((SUCCESS_COUNT++))
        log_info "Successfully synced $ORG"
    else
        ((FAIL_COUNT++))
        FAILED_ORGS+=("$ORG")
        log_warn "Failed to sync $ORG"
    fi

    echo "----------------------------------------"
done

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo "Total organizations: $(($SUCCESS_COUNT + $FAIL_COUNT))"
echo "Successful: $SUCCESS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ $FAIL_COUNT -gt 0 ]; then
    echo ""
    echo "Failed organizations:"
    for org in "${FAILED_ORGS[@]}"; do
        echo "  - $org"
    done
fi

echo "=========================================="

if [ $FAIL_COUNT -gt 0 ]; then
    exit 1
fi
