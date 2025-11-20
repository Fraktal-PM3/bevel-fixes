# Fraktal FireFly Kubernetes Deployment

Complete Helm charts for deploying FireFly on Kubernetes with Fabric blockchain.

## Quick Deploy

```bash
# 1. Start Kubernetes
minikube start

# 2. Install cert-manager (for TLS certificates)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
kubectl apply -f https://raw.githubusercontent.com/hyperledger/firefly-helm-charts/main/manifests/tls-issuers.yaml

# 3. Deploy PostgreSQL
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install firefly-postgres bitnami/postgresql \
  --set auth.username=postgres \
  --set auth.password=f1refly \
  --set auth.database=firefly

# 4. Deploy FabConnect
cd fabconnect
helm install fabconnect . -f values-dev.yaml
cd ..

# 5. Deploy FireFly
cd fraktal-firefly
helm dependency update
helm install fraktal-firefly-org1 . -f values-org1.yaml
```

## What Gets Deployed

- **PostgreSQL** - Database for FireFly state
- **FabConnect** - Fabric blockchain connector
- **FireFly Core** - Main FireFly service
- **DataExchange** - Private P2P messaging
- **IPFS** - Shared storage
- **Sandbox** - Web UI for testing

## Prerequisites

Running Fabric network with:

- Channel: `pm3`
- Chaincode: `firefly`
- Admin certificates in `fabric-samples/test-network/organizations/`

## Port Forward

```bash
# FireFly API
kubectl port-forward svc/fraktal-firefly-org1-firefly 8000:5000

# FabConnect API
kubectl port-forward svc/fabconnect-fabconnect 3000:3000

# Test
curl http://localhost:8000/api/v1/status
```

## Charts

- **fabconnect/** - Fabric connector service
- **fraktal-firefly/** - FireFly deployment (wraps official chart)

See individual chart READMEs for details.
