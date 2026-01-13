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

# Script parameters
ORG_NAME="${1}"
SECRET_NAME="${2:-fabconnect-msp}"
NETWORK_TYPE="${NETWORK_TYPE:-}"

# Usage function
usage() {
    cat <<EOF
Usage: $0 <org_name> [secret_name] [options]

Sync MSP credentials from HashiCorp Vault to Kubernetes secrets for FabConnect.

Arguments:
  org_name            Organization name (e.g., 'org1', 'manufacturer')
  secret_name         Kubernetes secret name (default: 'fabconnect-msp')

Environment Variables:
  VAULT_ADDR          Vault server address (default: http://localhost:8200)
  VAULT_TOKEN         Vault authentication token (default: mydevroot)
  VAULT_SECRET_PATH   Vault KV path (default: secretsv2)
  VAULT_MSP_PATH      Full Vault path to MSP (overrides auto-detection)
  NAMESPACE           Kubernetes namespace (default: default)
  NETWORK_TYPE        Network type prefix (e.g., 'fabric-', optional)

Examples:
  # Basic usage
  $0 org1

  # Custom secret name
  $0 org1 my-custom-msp-secret

  # With network type prefix
  NETWORK_TYPE=fabric- $0 manufacturer

  # Custom Vault path
  VAULT_MSP_PATH=secretsv2/fabric-manufacturer/users/admin-msp $0 manufacturer

  # Different namespace
  NAMESPACE=production $0 org1

EOF
    exit 1
}

# Check arguments
if [ -z "$ORG_NAME" ]; then
    echo "Error: Organization name is required"
    usage
fi

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

echo "=========================================="
echo "MSP Sync from Vault to Kubernetes"
echo "=========================================="
echo "Organization: $ORG_NAME"
echo "Secret Name: $SECRET_NAME"
echo "Namespace: $NAMESPACE"
echo "Vault Address: $VAULT_ADDR"
echo "=========================================="

# Check for required tools
for tool in vault minikube jq; do
    if ! command -v $tool &> /dev/null; then
        log_error "$tool is not installed. Please install it first."
        exit 1
    fi
done

# Export Vault configuration
export VAULT_ADDR
export VAULT_TOKEN

# Test Vault connection
log_info "Testing Vault connection..."
if ! vault status &> /dev/null; then
    log_error "Cannot connect to Vault at $VAULT_ADDR"
    exit 1
fi
log_info "Connected to Vault"

# Determine MSP path in Vault
if [ -n "$VAULT_MSP_PATH" ]; then
    MSP_PATH="$VAULT_MSP_PATH"
else
    # Try common path patterns
    ORG_NAME_LOWER=$(echo "$ORG_NAME" | tr '[:upper:]' '[:lower:]')
    ORG_NAME_WITH_PREFIX="local${ORG_NAME_LOWER}"

    # Pattern 1: Bevel local deployment pattern (most common)
    MSP_PATH="${VAULT_SECRET_PATH}/${ORG_NAME_WITH_PREFIX}/users/admin-msp"

    # Check if path exists
    if ! vault kv get "$MSP_PATH" &> /dev/null; then
        log_warn "Path not found: $MSP_PATH"

        # Pattern 2: Network type prefix pattern
        MSP_PATH="${VAULT_SECRET_PATH}/${NETWORK_TYPE}${ORG_NAME_LOWER}/users/admin-msp"

        if ! vault kv get "$MSP_PATH" &> /dev/null; then
            log_warn "Path not found: $MSP_PATH"

            # Pattern 3: Direct organization path
            MSP_PATH="${VAULT_SECRET_PATH}/${ORG_NAME_LOWER}/users/admin-msp"

            if ! vault kv get "$MSP_PATH" &> /dev/null; then
                log_warn "Path not found: $MSP_PATH"

                # Pattern 4: peerOrganizations path (legacy)
                MSP_PATH="${VAULT_SECRET_PATH}/${NETWORK_TYPE}${ORG_NAME_LOWER}/peerOrganizations/${ORG_NAME_LOWER}/users/admin/msp"

                if ! vault kv get "$MSP_PATH" &> /dev/null; then
                    log_error "Cannot find MSP data in Vault. Tried:"
                    echo "  - ${VAULT_SECRET_PATH}/${ORG_NAME_WITH_PREFIX}/users/admin-msp"
                    echo "  - ${VAULT_SECRET_PATH}/${NETWORK_TYPE}${ORG_NAME_LOWER}/users/admin-msp"
                    echo "  - ${VAULT_SECRET_PATH}/${ORG_NAME_LOWER}/users/admin-msp"
                    echo "  - ${VAULT_SECRET_PATH}/${NETWORK_TYPE}${ORG_NAME_LOWER}/peerOrganizations/${ORG_NAME_LOWER}/users/admin/msp"
                    echo ""
                    echo "Set VAULT_MSP_PATH environment variable to specify the exact path."
                    exit 1
                fi
            fi
        fi
    fi
fi

log_info "Using Vault path: $MSP_PATH"

# Create temporary directory for MSP files
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

# Create simple flat MSP structure
MSP_DIR="$TMP_DIR/msp"
mkdir -p "$MSP_DIR"/{admincerts,cacerts,keystore,signcerts,tlscacerts}

log_info "Fetching MSP data from Vault..."

# Fetch and save each MSP component
COMPONENTS=("admincerts" "cacerts" "keystore" "signcerts" "tlscacerts")
for component in "${COMPONENTS[@]}"; do
    log_info "Fetching $component..."

    # Get the data from Vault
    DATA=$(vault kv get -field="$component" "$MSP_PATH" 2>/dev/null || echo "")

    if [ -z "$DATA" ]; then
        log_warn "$component not found in Vault"
        continue
    fi

    # Determine filename based on component
    case $component in
        admincerts|signcerts)
            FILENAME="cert.pem"
            ;;
        cacerts)
            FILENAME="ca.pem"
            ;;
        tlscacerts)
            FILENAME="tlsca.pem"
            ;;
        keystore)
            FILENAME="key.pem"
            ;;
    esac

    # Save to file
    echo "$DATA" > "$MSP_DIR/$component/$FILENAME"
    log_info "Saved $component/$FILENAME ($(echo "$DATA" | wc -c) bytes)"
done

# Verify we have minimum required components
if [ ! -f "$MSP_DIR/cacerts/ca.pem" ] || [ ! -f "$MSP_DIR/signcerts/cert.pem" ] || [ ! -f "$MSP_DIR/keystore/key.pem" ]; then
    log_error "Missing required MSP components (cacerts, signcerts, or keystore)"
    exit 1
fi

log_info "MSP files prepared in temporary directory"

# Check Kubernetes connection
log_info "Checking Kubernetes connection..."
if ! minikube kubectl -- cluster-info &> /dev/null; then
    log_error "Cannot connect to Kubernetes cluster"
    exit 1
fi
log_info "Connected to Kubernetes"

# Create namespace if it doesn't exist
minikube kubectl -- create namespace "$NAMESPACE" --dry-run=client -o yaml | minikube kubectl -- apply -f - &> /dev/null
log_info "Namespace '$NAMESPACE' ready"

# Delete existing secret if it exists
if minikube kubectl -- get secret "$SECRET_NAME" -n "$NAMESPACE" &> /dev/null; then
    log_warn "Secret '$SECRET_NAME' already exists, deleting..."
    minikube kubectl -- delete secret "$SECRET_NAME" -n "$NAMESPACE"
fi

# Create Kubernetes secret from the MSP directory
# Files need to have __ separator for init container to process them
log_info "Creating Kubernetes secret '$SECRET_NAME'..."
minikube kubectl -- create secret generic "$SECRET_NAME" \
    --from-file=admincerts__cert.pem="$MSP_DIR/admincerts/cert.pem" \
    --from-file=cacerts__ca.pem="$MSP_DIR/cacerts/ca.pem" \
    --from-file=keystore__key.pem="$MSP_DIR/keystore/key.pem" \
    --from-file=signcerts__cert.pem="$MSP_DIR/signcerts/cert.pem" \
    --from-file=tlscacerts__tlsca.pem="$MSP_DIR/tlscacerts/tlsca.pem" \
    --namespace "$NAMESPACE"

log_info "Secret created successfully"

# Display secret contents (metadata only)
echo ""
echo "=========================================="
echo "Secret Details"
echo "=========================================="
minikube kubectl -- get secret "$SECRET_NAME" -n "$NAMESPACE" -o yaml | grep -E "^(apiVersion|kind|metadata:|  name:|  namespace:)" | grep -v "creationTimestamp\|resourceVersion\|uid"

echo ""
echo "Secret data keys:"
if minikube kubectl -- get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data}' | grep -q .; then
    minikube kubectl -- describe secret "$SECRET_NAME" -n "$NAMESPACE" | grep -A 100 "^Data" | tail -n +2 | head -n 20
else
    echo "  (no data keys found)"
fi

echo ""
echo "=========================================="
log_info "MSP sync complete!"
echo "=========================================="
echo ""
echo "The secret is ready to use with FabConnect."
echo "Make sure your values file references this secret:"
echo ""
echo "  fabconnect:"
echo "    msp:"
echo "      secretName: \"$SECRET_NAME\""
echo "      mountPath: \"/etc/firefly/organizations\""
echo ""
