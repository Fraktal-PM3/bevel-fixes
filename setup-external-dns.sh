#!/bin/bash
##############################################################################################
#  Copyright Accenture. All Rights Reserved.
#
#  SPDX-License-Identifier: Apache-2.0
##############################################################################################

set -e

echo "=================================="
echo "External DNS Setup for Bevel"
echo "=================================="
echo ""

# Path to k8s config file
export KUBECONFIG=/home/hedlund01/bevel-fixes/build/config

# Check if network.yaml exists
if [ ! -f "/home/hedlund01/bevel-fixes/build/network.yaml" ]; then
    echo "ERROR: network.yaml not found in build/ directory"
    exit 1
fi

# Extract DNS provider from network.yaml
DNS_PROVIDER=$(grep -A 10 "env:" /home/hedlund01/bevel-fixes/build/network.yaml | grep "external_dns_provider:" | awk '{print $2}')
EXTERNAL_DNS_ENABLED=$(grep -A 10 "env:" /home/hedlund01/bevel-fixes/build/network.yaml | grep "external_dns:" | awk '{print $2}')

if [ "$EXTERNAL_DNS_ENABLED" != "enabled" ]; then
    echo "External DNS is not enabled in network.yaml"
    echo "Skipping External DNS setup..."
    exit 0
fi

echo "DNS Provider detected: $DNS_PROVIDER"
echo ""

# Function to create Cloudflare secret
setup_cloudflare() {
    echo "Setting up Cloudflare credentials..."
    echo ""
    
    # Check if secret already exists
    if kubectl get secret cloudflare-api-token -n kube-system &> /dev/null; then
        echo "✓ Cloudflare API token secret already exists"
        return 0
    fi
    
    # Prompt for API token if not provided as environment variable
    if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
        echo "Please enter your Cloudflare API Token:"
        echo "(Create one at: https://dash.cloudflare.com/profile/api-tokens)"
        echo "Required permissions: Zone.Zone:Read, Zone.DNS:Edit"
        echo ""
        read -s CLOUDFLARE_API_TOKEN
        echo ""
    fi
    
    if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
        echo "ERROR: Cloudflare API token is required"
        exit 1
    fi
    
    # Create secret
    kubectl create secret generic cloudflare-api-token \
        --from-literal=cloudflare_api_token="$CLOUDFLARE_API_TOKEN" \
        -n kube-system
    
    echo "✓ Cloudflare API token secret created"
}

# Function to create AWS credentials secret
setup_aws() {
    echo "Setting up AWS credentials..."
    echo ""
    
    # Check if secret already exists
    if kubectl get secret aws-credentials -n kube-system &> /dev/null; then
        echo "✓ AWS credentials secret already exists"
        return 0
    fi
    
    # Prompt for AWS credentials if not provided as environment variables
    if [ -z "$AWS_ACCESS_KEY_ID" ]; then
        echo "Please enter your AWS Access Key ID:"
        read AWS_ACCESS_KEY_ID
    fi
    
    if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        echo "Please enter your AWS Secret Access Key:"
        read -s AWS_SECRET_ACCESS_KEY
        echo ""
    fi
    
    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        echo "ERROR: AWS credentials are required"
        exit 1
    fi
    
    # Create secret
    kubectl create secret generic aws-credentials \
        --from-literal=aws_access_key_id="$AWS_ACCESS_KEY_ID" \
        --from-literal=aws_secret_access_key="$AWS_SECRET_ACCESS_KEY" \
        -n kube-system
    
    echo "✓ AWS credentials secret created"
}

# Function to create GCP credentials secret
setup_gcp() {
    echo "Setting up GCP credentials..."
    echo ""
    
    # Check if secret already exists
    if kubectl get secret gcp-credentials -n kube-system &> /dev/null; then
        echo "✓ GCP credentials secret already exists"
        return 0
    fi
    
    # Prompt for service account JSON path
    if [ -z "$GCP_SERVICE_ACCOUNT_JSON" ]; then
        echo "Please enter the path to your GCP service account JSON file:"
        read GCP_SERVICE_ACCOUNT_JSON
    fi
    
    if [ ! -f "$GCP_SERVICE_ACCOUNT_JSON" ]; then
        echo "ERROR: GCP service account JSON file not found: $GCP_SERVICE_ACCOUNT_JSON"
        exit 1
    fi
    
    # Create secret
    kubectl create secret generic gcp-credentials \
        --from-file=credentials.json="$GCP_SERVICE_ACCOUNT_JSON" \
        -n kube-system
    
    echo "✓ GCP credentials secret created"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl is not installed or not in PATH"
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    echo "ERROR: Cannot connect to Kubernetes cluster"
    echo "Please ensure KUBECONFIG is set correctly and cluster is running"
    exit 1
fi

echo "✓ Kubernetes cluster is accessible"
echo ""

# Setup credentials based on provider
case "$DNS_PROVIDER" in
    cloudflare)
        setup_cloudflare
        ;;
    aws)
        setup_aws
        ;;
    google)
        setup_gcp
        ;;
    *)
        echo "ERROR: Unknown DNS provider: $DNS_PROVIDER"
        echo "Supported providers: cloudflare, aws, google"
        exit 1
        ;;
esac

echo ""
echo "=================================="
echo "✓ External DNS setup completed!"
echo "=================================="
echo ""
echo "The Ansible playbook will now deploy External DNS automatically."
echo "You can monitor External DNS with:"
echo "  kubectl get pods -n kube-system -l app=external-dns"
echo "  kubectl logs -n kube-system -l app=external-dns -f"
echo ""
