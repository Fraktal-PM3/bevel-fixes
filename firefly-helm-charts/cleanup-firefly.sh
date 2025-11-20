#!/bin/bash
##############################################################################################
#  Copyright Accenture. All Rights Reserved.
#
#  SPDX-License-Identifier: Apache-2.0
##############################################################################################

set -e

NAMESPACE="${NAMESPACE:-default}"
RELEASE_NAME="${RELEASE_NAME:-firefly}"
DELETE_PVC="${DELETE_PVC:-false}"

echo "=========================================="
echo "FireFly Cleanup Script"
echo "=========================================="
echo "Namespace: $NAMESPACE"
echo "Release: $RELEASE_NAME"
echo "Delete PVCs: $DELETE_PVC"
echo "=========================================="

# Check if release exists
if ! helm list -n $NAMESPACE | grep -q $RELEASE_NAME; then
    echo "Release $RELEASE_NAME not found in namespace $NAMESPACE"
    exit 1
fi

# Uninstall Helm release
echo ""
echo "Uninstalling Helm release $RELEASE_NAME..."
helm uninstall $RELEASE_NAME -n $NAMESPACE
echo "✓ Helm release uninstalled"

# Optionally delete PVCs
if [ "$DELETE_PVC" = "true" ]; then
    echo ""
    echo "Deleting persistent volume claims..."
    minikube kubectl -- delete pvc -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME || true
    echo "✓ PVCs deleted"
else
    echo ""
    echo "ℹ Persistent volume claims are retained."
    echo "  To delete them, run: minikube kubectl -- delete pvc -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME"
    echo "  Or set DELETE_PVC=true when running this script"
fi

# Clean up any leftover resources
echo ""
echo "Checking for leftover resources..."
LEFTOVER_PODS=$(minikube kubectl -- get pods -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME --no-headers 2>/dev/null | wc -l)
if [ $LEFTOVER_PODS -gt 0 ]; then
    echo "⚠ Warning: $LEFTOVER_PODS pod(s) still exist. They should terminate shortly."
fi

echo ""
echo "=========================================="
echo "✓ Cleanup complete!"
echo "=========================================="
