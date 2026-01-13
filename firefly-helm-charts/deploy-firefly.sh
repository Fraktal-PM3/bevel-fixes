#!/bin/bash
##############################################################################################
#  Copyright Accenture. All Rights Reserved.
#
#  SPDX-License-Identifier: Apache-2.0
##############################################################################################

set -e

NAMESPACE="${NAMESPACE:-default}"
RELEASE_NAME="${RELEASE_NAME:-firefly}"
VALUES_FILE="${VALUES_FILE:-./values/fabric-values.yaml}"

echo "=========================================="
echo "FireFly Deployment Script"
echo "=========================================="
echo "Namespace: $NAMESPACE"
echo "Release: $RELEASE_NAME"
echo "Values File: $VALUES_FILE"
echo "=========================================="

# Check if kubectl is configured
echo "Checking Kubernetes connection..."
if ! minikube kubectl -- cluster-info &> /dev/null; then
    echo "Error: Cannot connect to Kubernetes cluster. Please check your KUBECONFIG."
    exit 1
fi
echo "✓ Connected to Kubernetes cluster"

# Create namespace if it doesn't exist
echo ""
echo "Creating namespace $NAMESPACE if it doesn't exist..."
minikube kubectl -- create namespace $NAMESPACE --dry-run=client -o yaml | minikube kubectl -- apply -f -
echo "✓ Namespace ready"

# Install cert-manager for TLS certificates
echo ""
echo "Installing cert-manager..."
minikube kubectl -- create namespace cert-manager --dry-run=client -o yaml | minikube kubectl -- apply -f - || true
minikube kubectl -- apply -f https://github.com/jetstack/cert-manager/releases/download/v1.4.0/cert-manager.crds.yaml
helm repo add jetstack https://charts.jetstack.io --force-update || true
helm upgrade --install --skip-crds -n cert-manager cert-manager jetstack/cert-manager --wait
echo "✓ cert-manager installed"

# Apply TLS issuers
echo ""
echo "Applying TLS issuers..."
minikube kubectl -- apply -n cert-manager -f manifests/tls-issuers.yaml || echo "Warning: Could not apply TLS issuers"

# Update Helm dependencies
echo ""
echo "Updating Helm chart dependencies..."
cd charts/firefly
helm dependency update
cd ../..
echo "✓ Dependencies updated"

# Deploy FireFly with Fabric
echo ""
echo "Deploying FireFly..."
helm upgrade --install $RELEASE_NAME ./charts/firefly \
    -f $VALUES_FILE \
    --namespace $NAMESPACE \
    --timeout 10m \
    --wait
echo "✓ FireFly deployed"

# Wait for pods to be ready
echo ""
echo "Waiting for FireFly pods to be ready..."
minikube kubectl -- wait --for=condition=ready pod \
    -l app.kubernetes.io/instance=$RELEASE_NAME \
    -n $NAMESPACE \
    --timeout=600s || echo "Warning: Some pods may not be ready yet"

# Display deployment status
echo ""
echo "=========================================="
echo "Deployment Status"
echo "=========================================="
minikube kubectl -- get pods -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME
echo ""
minikube kubectl -- get svc -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME

echo ""
echo "=========================================="
echo "✓ FireFly deployment complete!"
echo "=========================================="
echo ""
echo "To access FireFly:"
echo "  minikube kubectl -- port-forward -n $NAMESPACE svc/$RELEASE_NAME 5000:5000"
echo ""
echo "To access the Sandbox UI:"
echo "  minikube kubectl -- port-forward -n $NAMESPACE svc/$RELEASE_NAME-sandbox 3001:3001"
echo ""
echo "To view logs:"
echo "  minikube kubectl -- logs -n $NAMESPACE -l app.kubernetes.io/component=core -f"
echo ""
