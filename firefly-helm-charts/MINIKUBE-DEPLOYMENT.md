# FireFly Deployment on Minikube

This guide explains how to deploy FireFly with all required dependencies (PostgreSQL, IPFS, and FabConnect) on Minikube.

## Prerequisites

1. **Minikube** running on your remote server
2. **kubectl** configured to access the Minikube cluster
3. **Helm 3.7+** installed
4. **Hyperledger Fabric network** already deployed (if using Fabric blockchain)

## Quick Start

### 1. Configure Your Fabric Network Details

Edit `values/minikube-fabric-values.yaml` and update the Fabric network endpoints:

```yaml
fabconnect:
  fabric:
    peerUrl: "grpcs://peer0.org1.example.com:7051"
    ordererUrl: "grpcs://orderer.example.com:7050"
    caUrl: "https://ca.org1.example.com:7054"
    organizationMspId: "Org1MSP"
    # ... etc
```

### 2. Create MSP Secret

If using Fabric, you need admin MSP credentials. Choose one method:

**Method A: Sync from Vault (Recommended for Bevel deployments)**

```bash
# Single organization
VAULT_TOKEN=mydevroot ./sync-msp-from-vault.sh org1

# Multiple organizations
VAULT_TOKEN=mydevroot ./sync-all-orgs-from-vault.sh org1 org2 org3
```

**Method B: Manual secret creation**

```bash
kubectl create secret generic fabconnect-msp \
  --from-file=./path/to/your/msp \
  --namespace default
```

See [VAULT-MSP-SYNC.md](./VAULT-MSP-SYNC.md) for detailed Vault sync instructions.

### 3. Deploy FireFly

Run the deployment script:

```bash
cd /path/to/firefly-helm-charts
./deploy-firefly.sh
```

Or with custom values:

```bash
VALUES_FILE=./values/minikube-fabric-values.yaml ./deploy-firefly.sh
```

### 4. Access FireFly

Once deployed, access FireFly services:

**FireFly API:**
```bash
kubectl port-forward -n default svc/firefly 5000:5000
```
Then open: http://localhost:5000/api

**Sandbox UI:**
```bash
kubectl port-forward -n default svc/firefly-sandbox 3001:3001
```
Then open: http://localhost:3001

## What Gets Deployed

The deployment script automatically installs:

1. **cert-manager** - For TLS certificate management
2. **PostgreSQL** - Built-in database (StatefulSet with 10Gi storage)
3. **IPFS** - Built-in shared storage (StatefulSet with 10Gi storage)
4. **FabConnect** - Hyperledger Fabric connector
5. **FireFly Core** - Main FireFly node
6. **Data Exchange** - Peer-to-peer communication service
7. **Sandbox UI** - Web interface for testing

## Environment Variables

Customize the deployment with environment variables:

```bash
NAMESPACE=firefly \
RELEASE_NAME=my-firefly \
VALUES_FILE=./values/custom-values.yaml \
./deploy-firefly.sh
```

## Deployed Components

After successful deployment, you should see these pods:

```bash
kubectl get pods -n default
```

Expected pods:
- `firefly-0` - FireFly core StatefulSet
- `firefly-dx-0` - Data exchange StatefulSet
- `firefly-postgres-0` - PostgreSQL StatefulSet
- `firefly-ipfs-0` - IPFS StatefulSet
- `firefly-fabconnect-*` - FabConnect deployment
- `firefly-sandbox-*` - Sandbox UI deployment

## Configuration Options

### Using External PostgreSQL

If you want to use an external PostgreSQL instead of the built-in one:

```yaml
postgres:
  enabled: false

config:
  postgresUrl: "postgres://user:pass@external-host:5432/firefly?sslmode=disable"
```

### Using External IPFS

If you want to use an external IPFS node:

```yaml
ipfs:
  enabled: false

config:
  ipfsApiUrl: "http://external-ipfs:5001"
  ipfsGatewayUrl: "http://external-ipfs:8080"
```

### Disable Sandbox UI

```yaml
sandbox:
  enabled: false
```

## Troubleshooting

### Check Pod Status
```bash
kubectl get pods -n default
kubectl describe pod <pod-name> -n default
```

### View Logs
```bash
# FireFly Core logs
kubectl logs -n default firefly-0 -f

# FabConnect logs
kubectl logs -n default -l app.kubernetes.io/name=fabconnect -f

# PostgreSQL logs
kubectl logs -n default firefly-postgres-0 -f
```

### Check Services
```bash
kubectl get svc -n default
```

### Verify Helm Release
```bash
helm list -n default
helm status firefly -n default
```

## Uninstalling

To remove the FireFly deployment:

```bash
helm uninstall firefly -n default
```

To also remove persistent volumes:

```bash
kubectl delete pvc -n default -l app.kubernetes.io/instance=firefly
```

## Advanced Usage

### Multiparty Mode

To enable advanced FireFly features after deployment:

```bash
./hack/multiparty.sh
```

Then upgrade the deployment with multiparty values:

```bash
helm upgrade firefly ./charts/firefly \
  -f ./values/minikube-fabric-values.yaml \
  -f ./hack/multiparty-values.yaml \
  -n default
```

### Custom Storage Classes

If your cluster has custom storage classes:

```yaml
postgres:
  persistentVolume:
    storageClass: "my-storage-class"
    size: 20Gi

ipfs:
  persistentVolume:
    storageClass: "my-storage-class"
    size: 20Gi
```

### Resource Limits

Adjust resources based on your cluster capacity:

```yaml
core:
  resources:
    limits:
      cpu: 1000m
      memory: 1Gi
    requests:
      cpu: 250m
      memory: 512Mi

postgres:
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
```

## Next Steps

After deployment:

1. Access the Sandbox UI to test FireFly functionality
2. Register your node with the network (if using multiparty mode)
3. Deploy smart contracts or chaincode
4. Start sending messages and transferring data

For more information, see the [FireFly Documentation](https://hyperledger.github.io/firefly/).
