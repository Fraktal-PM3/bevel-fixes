# Scripts Overview

This directory contains several scripts to simplify FireFly deployment and management.

## Deployment Scripts

### `deploy-firefly.sh`
**Purpose:** One-command deployment of FireFly with all dependencies

**Usage:**
```bash
./deploy-firefly.sh
```

**What it does:**
- Installs cert-manager for TLS certificates
- Updates Helm chart dependencies
- Deploys FireFly with PostgreSQL, IPFS, FabConnect, etc.
- Waits for all pods to be ready

**Environment Variables:**
- `NAMESPACE` - Kubernetes namespace (default: `default`)
- `RELEASE_NAME` - Helm release name (default: `firefly`)
- `VALUES_FILE` - Values file to use (default: `./values/fabric-values.yaml`)

**Example:**
```bash
NAMESPACE=production RELEASE_NAME=firefly-prod ./deploy-firefly.sh
```

---

### `cleanup-firefly.sh`
**Purpose:** Clean removal of FireFly deployment

**Usage:**
```bash
./cleanup-firefly.sh
```

**What it does:**
- Uninstalls Helm release
- Optionally deletes persistent volume claims

**Environment Variables:**
- `NAMESPACE` - Kubernetes namespace (default: `default`)
- `RELEASE_NAME` - Helm release name (default: `firefly`)
- `DELETE_PVC` - Delete PVCs (default: `false`, set to `true` to delete data)

**Example:**
```bash
# Keep data
./cleanup-firefly.sh

# Delete everything including data
DELETE_PVC=true ./cleanup-firefly.sh
```

---

## Vault Integration Scripts

### `sync-msp-from-vault.sh`
**Purpose:** Sync single organization admin MSP from HashiCorp Vault to Kubernetes

**Usage:**
```bash
./sync-msp-from-vault.sh <org_name> [secret_name]
```

**What it does:**
- Connects to HashiCorp Vault
- Reads admin MSP (admincerts, cacerts, keystore, signcerts, tlscacerts)
- Creates Kubernetes secret with proper MSP structure
- Ready for use with FabConnect

**Environment Variables:**
- `VAULT_ADDR` - Vault server address (default: `http://localhost:8200`)
- `VAULT_TOKEN` - Vault authentication token (default: `mydevroot`)
- `VAULT_SECRET_PATH` - Vault KV path (default: `secretsv2`)
- `VAULT_MSP_PATH` - Full Vault path (overrides auto-detection)
- `NAMESPACE` - Kubernetes namespace (default: `default`)
- `NETWORK_TYPE` - Network type prefix (e.g., `fabric-`)

**Examples:**
```bash
# Basic usage
VAULT_TOKEN=mydevroot ./sync-msp-from-vault.sh org1

# Custom secret name
./sync-msp-from-vault.sh org1 my-org1-admin-msp

# With network type prefix
NETWORK_TYPE=fabric- ./sync-msp-from-vault.sh manufacturer

# Custom Vault path
VAULT_MSP_PATH=secretsv2/custom/path/msp ./sync-msp-from-vault.sh org1
```

---

### `sync-all-orgs-from-vault.sh`
**Purpose:** Bulk sync multiple organizations from Vault

**Usage:**
```bash
./sync-all-orgs-from-vault.sh <org1> [org2] [org3] ...
```

**What it does:**
- Calls `sync-msp-from-vault.sh` for each organization
- Creates separate secrets for each org (`org1-msp`, `org2-msp`, etc.)
- Reports success/failure summary

**Environment Variables:**
Same as `sync-msp-from-vault.sh`

**Example:**
```bash
# Sync three organizations
VAULT_TOKEN=mydevroot ./sync-all-orgs-from-vault.sh org1 org2 org3

# With custom configuration
VAULT_ADDR=http://vault.example.com:8200 \
VAULT_TOKEN=s.token \
NAMESPACE=production \
./sync-all-orgs-from-vault.sh manufacturer carrier warehouse
```

---

## Complete Workflow

Here's a typical workflow for deploying FireFly with Fabric:

```bash
cd /path/to/firefly-helm-charts

# Step 1: Sync admin MSP from Vault
VAULT_TOKEN=mydevroot ./sync-msp-from-vault.sh org1

# Step 2: Update values file with network details
# Edit values/fabric-values.yaml with your Fabric network endpoints

# Step 3: Deploy FireFly
./deploy-firefly.sh

# Step 4: Access FireFly
kubectl port-forward svc/firefly 5000:5000
kubectl port-forward svc/firefly-sandbox 3001:3001
```

## Quick Reference

| Task | Command |
|------|---------|
| Deploy FireFly | `./deploy-firefly.sh` |
| Sync MSP (single org) | `./sync-msp-from-vault.sh org1` |
| Sync MSP (multiple) | `./sync-all-orgs-from-vault.sh org1 org2 org3` |
| Access FireFly API | `kubectl port-forward svc/firefly 5000:5000` |
| Access Sandbox | `kubectl port-forward svc/firefly-sandbox 3001:3001` |
| View logs | `kubectl logs firefly-0 -f` |
| Check pods | `kubectl get pods` |
| Cleanup (keep data) | `./cleanup-firefly.sh` |
| Cleanup (delete all) | `DELETE_PVC=true ./cleanup-firefly.sh` |

## Documentation

- **[QUICKSTART.md](./QUICKSTART.md)** - Quick start guide (read this first!)
- **[MINIKUBE-DEPLOYMENT.md](./MINIKUBE-DEPLOYMENT.md)** - Comprehensive deployment guide
- **[VAULT-MSP-SYNC.md](./VAULT-MSP-SYNC.md)** - Detailed Vault integration documentation
- **[README.md](./README.md)** - Chart documentation and configuration reference

## Prerequisites

All scripts require:
- **kubectl** - Configured for your cluster
- **helm** - Version 3.7+

Vault scripts additionally require:
- **vault** CLI - For Vault operations
- **jq** - For JSON parsing

## Troubleshooting

### Script not executable
```bash
chmod +x *.sh
```

### Cannot find scripts
```bash
cd /path/to/firefly-helm-charts
ls -la *.sh
```

### Vault connection issues
```bash
# Test Vault connection
vault status

# Set correct address
export VAULT_ADDR=http://your-vault:8200
export VAULT_TOKEN=your-token
```

### Kubernetes connection issues
```bash
# Test kubectl
kubectl cluster-info
kubectl get nodes

# Check KUBECONFIG
echo $KUBECONFIG
```

## Support

For issues or questions:
1. Check the relevant documentation (QUICKSTART.md, MINIKUBE-DEPLOYMENT.md, etc.)
2. Review script output for error messages
3. Use `--help` or `-h` flag on scripts (where supported)
4. Check Kubernetes pod logs: `kubectl logs <pod-name>`
