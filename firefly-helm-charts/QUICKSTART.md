# FireFly Quick Start Guide

## One-Command Deployment

Deploy FireFly with PostgreSQL, IPFS, and FabConnect in one command:

```bash
cd /path/to/firefly-helm-charts
./deploy-firefly.sh
```

That's it! The script will:
- ✓ Install cert-manager
- ✓ Deploy PostgreSQL (with 10Gi storage)
- ✓ Deploy IPFS (with 10Gi storage)
- ✓ Deploy FabConnect (if using Fabric)
- ✓ Deploy FireFly Core
- ✓ Deploy Data Exchange
- ✓ Deploy Sandbox UI

## Before You Start

### 1. Sync Admin MSP from Vault (for Fabric)

If you have MSP in HashiCorp Vault (from Bevel deployment):

```bash
# Single organization
VAULT_TOKEN=mydevroot ./sync-msp-from-vault.sh org1

# Multiple organizations
VAULT_TOKEN=mydevroot ./sync-all-orgs-from-vault.sh org1 org2 org3
```

Or manually create MSP secret:

```bash
kubectl create secret generic fabconnect-msp \
  --from-file=./path/to/msp \
  --namespace default
```

See [VAULT-MSP-SYNC.md](./VAULT-MSP-SYNC.md) for detailed instructions.

### 2. Update Fabric Network Configuration

Edit `values/fabric-values.yaml` or `values/minikube-fabric-values.yaml`:

```yaml
fabconnect:
  msp:
    secretName: "org1-msp"  # Use the synced secret name

  fabric:
    peerUrl: "grpcs://your-peer:7051"
    ordererUrl: "grpcs://your-orderer:7050"
    caUrl: "https://your-ca:7054"
    organizationMspId: "YourOrgMSP"
```

## Access FireFly

### FireFly API
```bash
kubectl port-forward svc/firefly 5000:5000
```
Open: http://localhost:5000/api

### Sandbox UI
```bash
kubectl port-forward svc/firefly-sandbox 3001:3001
```
Open: http://localhost:3001

## Custom Configuration

Use custom values file:
```bash
VALUES_FILE=./values/minikube-fabric-values.yaml ./deploy-firefly.sh
```

Use different namespace:
```bash
NAMESPACE=my-namespace ./deploy-firefly.sh
```

Use different release name:
```bash
RELEASE_NAME=my-firefly ./deploy-firefly.sh
```

Combine options:
```bash
NAMESPACE=production \
RELEASE_NAME=firefly-prod \
VALUES_FILE=./values/production-values.yaml \
./deploy-firefly.sh
```

## Cleanup

Remove FireFly (keep data):
```bash
./cleanup-firefly.sh
```

Remove FireFly and delete all data:
```bash
DELETE_PVC=true ./cleanup-firefly.sh
```

## Troubleshooting

### View logs
```bash
# All FireFly logs
kubectl logs -l app.kubernetes.io/instance=firefly -f

# Just core logs
kubectl logs firefly-0 -f

# FabConnect logs
kubectl logs -l app.kubernetes.io/component=fabconnect -f
```

### Check status
```bash
kubectl get pods
kubectl get svc
helm list
```

### Describe pod issues
```bash
kubectl describe pod <pod-name>
```

## What's Deployed

| Component | Type | Purpose |
|-----------|------|---------|
| `firefly-0` | StatefulSet | FireFly core node |
| `firefly-dx-0` | StatefulSet | P2P data exchange |
| `firefly-postgres-0` | StatefulSet | PostgreSQL database |
| `firefly-ipfs-0` | StatefulSet | IPFS shared storage |
| `firefly-fabconnect-*` | Deployment | Fabric blockchain connector |
| `firefly-sandbox-*` | Deployment | Web UI for testing |

## Storage

Each component uses persistent storage:
- PostgreSQL: 10Gi (database data)
- IPFS: 10Gi (shared files)
- Data Exchange: 2Gi (peer data + blobs)
- FabConnect: 5Gi (transaction receipts)

## Next Steps

1. **Test the API**: Access http://localhost:5000/api
2. **Use Sandbox**: Access http://localhost:3001
3. **Enable Multiparty**: Run `./hack/multiparty.sh`
4. **Deploy Contracts**: Use the FireFly API or Sandbox

For detailed information, see [MINIKUBE-DEPLOYMENT.md](./MINIKUBE-DEPLOYMENT.md)
