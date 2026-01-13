# Syncing MSP from HashiCorp Vault to Kubernetes

This guide explains how to sync Fabric admin MSP credentials from HashiCorp Vault to Kubernetes secrets for use with FabConnect.

## Overview

When deploying Fabric networks with Hyperledger Bevel, admin identities (MSP) are stored in HashiCorp Vault. FabConnect needs these admin credentials to interact with the Fabric network.

These scripts automate the process of:
1. Reading admin MSP from Vault (admincerts, cacerts, keystore, signcerts, tlscacerts)
2. Creating properly structured Kubernetes secrets
3. Making them available to FabConnect pods

## Prerequisites

- **HashiCorp Vault** running and accessible (default: http://localhost:8200)
- **Vault token** with read access to MSP secrets
- **kubectl** configured for your Kubernetes cluster
- **vault** CLI installed
- **jq** installed (for JSON parsing)

## Quick Start

### Single Organization

Sync admin MSP for one organization:

```bash
cd /path/to/firefly-helm-charts

# Basic usage (Vault at localhost:8200, token: mydevroot)
./sync-msp-from-vault.sh org1

# Custom Vault configuration
VAULT_ADDR=http://vault.example.com:8200 \
VAULT_TOKEN=s.your-vault-token \
./sync-msp-from-vault.sh org1
```

### Multiple Organizations

Sync admin MSP for multiple organizations:

```bash
# Sync org1, org2, and org3
./sync-all-orgs-from-vault.sh org1 org2 org3

# With custom configuration
VAULT_ADDR=http://vault.example.com:8200 \
VAULT_TOKEN=s.your-vault-token \
NAMESPACE=production \
./sync-all-orgs-from-vault.sh manufacturer carrier warehouse
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `VAULT_ADDR` | Vault server address | `http://localhost:8200` |
| `VAULT_TOKEN` | Vault authentication token | `mydevroot` |
| `VAULT_SECRET_PATH` | Vault KV secret path | `secretsv2` |
| `VAULT_MSP_PATH` | Full path to MSP (overrides auto-detection) | Auto-detected |
| `NAMESPACE` | Kubernetes namespace | `default` |
| `NETWORK_TYPE` | Network type prefix (e.g., 'fabric-') | Empty |

## Vault Path Detection

The script automatically tries to find MSP data in these paths (in order):

1. `secretsv2/{NETWORK_TYPE}{org}/peerOrganizations/{org}/users/admin/msp`
2. `secretsv2/{NETWORK_TYPE}{org}/users/admin-msp`
3. `secretsv2/{org}/users/admin-msp`

### Custom Path

If your Vault uses a different structure, specify the exact path:

```bash
VAULT_MSP_PATH=secretsv2/custom/path/to/msp \
./sync-msp-from-vault.sh org1
```

## What Gets Created

For organization `org1`, the script creates a Kubernetes secret `org1-msp` (or `fabconnect-msp` if no org name specified) with this structure:

```
org1-msp/
├── admincerts/
│   └── Admin@org1-cert.pem
├── cacerts/
│   └── ca-org1-cert.pem
├── keystore/
│   └── server.key
├── signcerts/
│   └── server.crt
└── tlscacerts/
    └── tlsca-org1-cert.pem
```

This structure matches what FabConnect expects when mounted at `/etc/firefly/organizations`.

## Using with FabConnect

After syncing MSP, reference the secret in your Helm values:

```yaml
fabconnect:
  enabled: true

  # Reference the synced MSP secret
  msp:
    secretName: "org1-msp"  # Or whatever secret name you used
    mountPath: "/etc/firefly/organizations"

  # Fabric configuration
  fabric:
    organizationName: "org1.example.com"
    organizationMspId: "Org1MSP"
    # ... other Fabric settings
```

## Complete Workflow Example

### 1. Sync MSP from Vault

```bash
cd /path/to/firefly-helm-charts

# Sync admin MSP for org1
VAULT_TOKEN=mydevroot ./sync-msp-from-vault.sh org1
```

Expected output:
```
==========================================
MSP Sync from Vault to Kubernetes
==========================================
Organization: org1
Secret Name: org1-msp
Namespace: default
Vault Address: http://localhost:8200
==========================================
✓ Testing Vault connection...
✓ Connected to Vault
✓ Using Vault path: secretsv2/org1/users/admin-msp
✓ Fetching MSP data from Vault...
✓ Fetching admincerts...
✓ Saved admincerts/Admin@org1-cert.pem
✓ Fetching cacerts...
✓ Saved cacerts/ca-org1-cert.pem
✓ Fetching keystore...
✓ Saved keystore/server.key
✓ Fetching signcerts...
✓ Saved signcerts/server.crt
✓ Fetching tlscacerts...
✓ Saved tlscacerts/tlsca-org1-cert.pem
✓ Secret created successfully
==========================================
✓ MSP sync complete!
==========================================
```

### 2. Verify Secret

```bash
kubectl get secret org1-msp -n default

kubectl get secret org1-msp -n default -o json | jq -r '.data | keys[]'
```

Expected output:
```
admincerts
cacerts
keystore
signcerts
tlscacerts
```

### 3. Update Values File

Edit `values/fabric-values.yaml`:

```yaml
fabconnect:
  enabled: true

  msp:
    secretName: "org1-msp"
    mountPath: "/etc/firefly/organizations"

  fabric:
    peerUrl: "grpcs://peer0.org1.example.com:7051"
    ordererUrl: "grpcs://orderer.example.com:7050"
    # ... rest of config
```

### 4. Deploy FireFly

```bash
./deploy-firefly.sh
```

## Troubleshooting

### Cannot connect to Vault

```
✗ Cannot connect to Vault at http://localhost:8200
```

**Solution:** Check Vault is running and accessible:
```bash
vault status
```

If Vault is on a different host/port:
```bash
VAULT_ADDR=http://your-vault:8200 ./sync-msp-from-vault.sh org1
```

### MSP path not found

```
✗ Cannot find MSP data in Vault
```

**Solution:** Check available paths in Vault:
```bash
vault kv list secretsv2/
vault kv list secretsv2/org1/
```

Set explicit path:
```bash
VAULT_MSP_PATH=secretsv2/your/actual/path/msp ./sync-msp-from-vault.sh org1
```

### Missing MSP components

```
✗ Missing required MSP components (cacerts or signcerts)
```

**Solution:** Verify Vault contains all required fields:
```bash
vault kv get secretsv2/org1/users/admin-msp
```

Should contain: `admincerts`, `cacerts`, `keystore`, `signcerts`, `tlscacerts`

### Vault token expired

```
Error making API request.
```

**Solution:** Get a new Vault token and set it:
```bash
export VAULT_TOKEN=s.new-token-here
./sync-msp-from-vault.sh org1
```

### kubectl cannot connect

```
✗ Cannot connect to Kubernetes cluster
```

**Solution:** Check kubectl configuration:
```bash
kubectl cluster-info
kubectl get nodes
```

## Advanced Usage

### Different Secret Names

Create multiple secrets from same org:

```bash
# Admin secret
./sync-msp-from-vault.sh org1 org1-admin-msp

# User secret (if you modify script to read user MSP)
./sync-msp-from-vault.sh org1 org1-user1-msp
```

### Different Namespaces

Sync to different namespaces:

```bash
# Production namespace
NAMESPACE=production ./sync-msp-from-vault.sh org1

# Development namespace
NAMESPACE=development ./sync-msp-from-vault.sh org1
```

### Network Type Prefix

If your Vault uses prefixes like `fabric-org1`:

```bash
NETWORK_TYPE=fabric- ./sync-msp-from-vault.sh org1
```

This will look for: `secretsv2/fabric-org1/users/admin-msp`

### Automation

Include in deployment script:

```bash
#!/bin/bash
set -e

# Sync MSP first
./sync-all-orgs-from-vault.sh org1 org2 org3

# Then deploy FireFly
./deploy-firefly.sh
```

## Security Considerations

1. **Vault Token**: Use least-privilege tokens that can only read necessary paths
2. **Secrets**: Kubernetes secrets are base64-encoded but not encrypted by default
3. **Enable encryption at rest** in your Kubernetes cluster
4. **Use RBAC** to restrict access to secrets
5. **Rotate credentials** regularly

## See Also

- [QUICKSTART.md](./QUICKSTART.md) - Quick deployment guide
- [MINIKUBE-DEPLOYMENT.md](./MINIKUBE-DEPLOYMENT.md) - Full deployment documentation
- [Hyperledger Fabric MSP](https://hyperledger-fabric.readthedocs.io/en/latest/msp.html) - MSP concept documentation
