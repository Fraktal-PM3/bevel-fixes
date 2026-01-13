# Using FireFly with FabConnect - Complete Deployment Guide

## Overview

This guide explains how to deploy Hyperledger FireFly with FabConnect to connect to a Hyperledger Fabric network using the Helm charts in this repository.

## Prerequisites Checklist

Before deploying, ensure you have:

1. **Hyperledger Fabric Network Running**:
   - Accessible peer(s), orderer(s), and CA
   - Note down the gRPC/HTTPS URLs

2. **Fabric Channel & Chaincode**:
   - Channel created (e.g., "firefly")
   - FireFly chaincode deployed on the channel

3. **MSP Credentials**:
   - Admin user's MSP directory with certificates
   - TLS certificates for peers/orderers

4. **Kubernetes Cluster**:
   - With persistent volume provisioner
   - PostgreSQL (for FireFly database)
   - IPFS (for shared storage)

---

## Step-by-Step Deployment

### Step 1: Prepare MSP Secret

Create a Kubernetes secret with your Fabric MSP credentials:

```bash
# Create the secret from your Fabric crypto-config directory
kubectl create secret generic fabconnect-msp \
  --from-file=/path/to/fabric/crypto-config \
  --namespace=default
```

Your MSP directory should contain:
```
crypto-config/
├── peerOrganizations/
│   └── org1.example.com/
│       ├── msp/
│       ├── peers/
│       └── users/
└── ordererOrganizations/
    └── example.com/
```

### Step 2: Create Custom Values File

Create a file called `my-fabric-values.yaml`:

```yaml
# FireFly Core Configuration
config:
  # Enable debug for troubleshooting
  debugEnabled: true
  adminEnabled: true

  # Organization details
  organizationName: "org1"

  # Set Fabric as blockchain
  defaultBlockchainType: "fabric"

  # FabConnect settings (auto-discovered from subchart)
  fabconnectUrl: ""  # Leave empty - auto-discovered
  fabconnectChannel: "firefly"
  fabconnectChaincode: "firefly"
  fabconnectSigner: "admin"  # Your Fabric identity name

  # Database (required)
  postgresUrl: "postgres://postgres:password@postgresql:5432/firefly?sslmode=disable"
  postgresAutomigrate: true

  # IPFS for shared storage (required for multiparty)
  ipfsApiUrl: "http://ipfs:5001"
  ipfsGatewayUrl: "http://ipfs:8080"

  # Enable multiparty mode
  multipartyEnabled: true

# Enable data exchange for peer-to-peer messaging
dataexchange:
  enabled: true
  certificate:
    enabled: true
    issuerRef:
      kind: ClusterIssuer
      name: selfsigned-ca

# FabConnect Configuration (deployed as subchart)
fabconnect:
  enabled: true

  # YOUR Fabric network endpoints
  fabric:
    peerUrl: "grpcs://peer0.org1.example.com:7051"
    ordererUrl: "grpcs://orderer.example.com:7050"
    caUrl: "https://ca.org1.example.com:7054"

    # YOUR organization details
    organizationName: "org1.example.com"
    organizationMspId: "Org1MSP"

    # YOUR channel and chaincode names
    channelName: "firefly"
    chaincodeName: "firefly"

    # CA enrollment credentials
    enrollId: "admin"
    enrollSecret: "adminpw"

  # Reference the MSP secret you created
  msp:
    secretName: "fabconnect-msp"
    mountPath: "/etc/firefly/organizations"

  # Resource allocation
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 100m
      memory: 128Mi

  # Storage for transaction receipts and events
  persistentVolume:
    size: 5Gi
    storageClass: ""  # Use default

# FireFly Core settings
core:
  enabled: true

# Optional: Enable sandbox UI
sandbox:
  enabled: true
```

### Step 3: Install Dependencies

If using a local cluster (like kind), install required dependencies:

```bash
# Create kind cluster
make kind

# Install dependencies: cert-manager, PostgreSQL, IPFS
make deps
```

Or manually install:
```bash
# PostgreSQL
helm install postgresql oci://registry-1.docker.io/bitnamicharts/postgresql \
  --set auth.postgresPassword=password

# IPFS
helm install ipfs ./charts/ipfs

# cert-manager (for TLS certificates)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
```

### Step 4: Update Chart Dependencies

```bash
cd firefly-helm-charts/charts/firefly
helm dep update
```

This downloads the `firefly-fabconnect` chart as a dependency.

### Step 5: Deploy FireFly + FabConnect

```bash
helm install firefly ./charts/firefly \
  -f my-fabric-values.yaml \
  --namespace default
```

### Step 6: Verify Deployment

```bash
# Check all pods are running
kubectl get pods

# Expected output:
# firefly-0                    1/1     Running
# firefly-dataexchange-0       1/1     Running
# firefly-fabconnect-0         1/1     Running
# postgresql-0                 1/1     Running
# ipfs-0                       1/1     Running

# Check FabConnect logs
kubectl logs firefly-fabconnect-0 -f

# Check FireFly logs
kubectl logs firefly-0 -f
```

### Step 7: Access FireFly

```bash
# Port-forward to access FireFly API
kubectl port-forward svc/firefly 5000:5000

# Port-forward for Sandbox UI (if enabled)
kubectl port-forward svc/firefly-sandbox 3000:3000

# Test FireFly API
curl http://localhost:5000/api/v1/status

# Access Sandbox UI
open http://localhost:3000
```

---

## How the Integration Works

### Automatic Service Discovery

When `fabconnect.enabled: true`, FireFly automatically discovers the FabConnect service:

```
FabConnect URL: http://firefly-fabconnect.default.svc:3000
```

The main FireFly chart configures this in the core config (see `charts/firefly/templates/_helpers.tpl` lines 216-482).

### Communication Flow

```
┌─────────────┐         ┌──────────────┐         ┌─────────────────┐
│   FireFly   │ ──REST──│  FabConnect  │ ──gRPC──│  Fabric Network │
│    Core     │         │  Connector   │         │  (Peer/Orderer) │
└─────────────┘         └──────────────┘         └─────────────────┘
       │                        │
       │                   ┌────▼─────┐
       │                   │ LevelDB  │
       │                   │ (Events) │
       │                   └──────────┘
       │
   ┌───▼──────┐
   │PostgreSQL│
   │(Metadata)│
   └──────────┘
```

1. **FireFly** sends blockchain transactions via REST API to **FabConnect**
2. **FabConnect** translates REST calls to Fabric gRPC SDK calls
3. **FabConnect** submits transactions to Fabric peers/orderers
4. **FabConnect** listens for chaincode events and stores them in LevelDB
5. **FabConnect** sends event webhooks back to **FireFly**
6. **FireFly** processes events and updates PostgreSQL

---

## Testing the Integration

### 1. Check FireFly Status

```bash
curl http://localhost:5000/api/v1/status | jq
```

Expected: `"status": "ready"`

### 2. Check FabConnect Status

```bash
kubectl port-forward svc/firefly-fabconnect 3000:3000
curl http://localhost:3000/status | jq
```

### 3. Submit a Test Transaction

Using the FireFly API:

```bash
# Create a message (broadcasts to all parties)
curl -X POST http://localhost:5000/api/v1/namespaces/default/messages/broadcast \
  -H "Content-Type: application/json" \
  -d '{
    "data": [{
      "value": "Hello from FireFly on Fabric!"
    }]
  }'
```

### 4. Check Transaction in FabConnect Logs

```bash
kubectl logs firefly-fabconnect-0 | grep -i transaction
```

You should see transaction submissions and confirmations.

---

## Enabling Multiparty Mode

Multiparty mode enables advanced FireFly features for multi-organization collaboration:
- **Broadcast messaging** with blockchain anchoring
- **Private peer-to-peer messaging** via DataExchange
- **Organization and node registry** on the blockchain
- **Event-driven architecture** with automatic webhooks
- **Consensus and ordering** through Fabric

### Prerequisites for Multiparty

Before enabling multiparty mode, ensure:

1. **FireFly Chaincode Deployed**: The FireFly chaincode must be installed on your Fabric channel
   - Repository: https://github.com/hyperledger/firefly-fabconnect/tree/main/test/firefly-go
   - Must be approved and committed by all organizations on the channel

2. **DataExchange Enabled**: Required for private messaging between organizations
   ```yaml
   dataexchange:
     enabled: true
     certificate:
       enabled: true
   ```

3. **Multiparty Enabled in Config**:
   ```yaml
   config:
     multipartyEnabled: true
   ```

### Verify FireFly Chaincode Deployment

Check that the FireFly chaincode is deployed on your Fabric channel:

```bash
# Connect to a Fabric peer
kubectl exec -it fabric-peer0-org1-0 -- bash

# Check committed chaincodes on channel
peer lifecycle chaincode querycommitted -C firefly

# Expected output should show "firefly" chaincode
# Committed chaincode definition for chaincode 'firefly' on channel 'firefly':
# Version: 1.0, Sequence: 1, ...
```

If not deployed, install the FireFly chaincode:

```bash
# Package the chaincode
peer lifecycle chaincode package firefly.tar.gz \
  --path /path/to/firefly-fabconnect/test/firefly-go \
  --lang golang \
  --label firefly_1.0

# Install on all peers (repeat for each org)
peer lifecycle chaincode install firefly.tar.gz

# Get package ID
peer lifecycle chaincode queryinstalled

# Approve for your org
peer lifecycle chaincode approveformyorg \
  --channelID firefly \
  --name firefly \
  --version 1.0 \
  --package-id firefly_1.0:abc123... \
  --sequence 1 \
  --tls --cafile $ORDERER_CA

# Commit (after all orgs approve)
peer lifecycle chaincode commit \
  --channelID firefly \
  --name firefly \
  --version 1.0 \
  --sequence 1 \
  --tls --cafile $ORDERER_CA \
  --peerAddresses peer0.org1.example.com:7051 \
  --tlsRootCertFiles $ORG1_TLS_ROOTCERT
```

### Check Multiparty Status

After deployment with `multipartyEnabled: true`, check the status:

```bash
# Port forward to FireFly API
kubectl port-forward svc/firefly 5000:5000

# Check multiparty status
curl http://localhost:5000/api/v1/namespaces/default/status | jq
```

Expected output:
```json
{
  "namespace": {
    "name": "default",
    "networkName": "default"
  },
  "org": {
    "name": "org1",
    "registered": false,
    "verifiers": []
  },
  "node": {
    "name": "firefly-org1",
    "registered": false
  },
  "plugins": {
    "blockchain": ["fabric0"],
    "dataexchange": ["dataexchange0"],
    "database": ["database0"],
    "sharedstorage": ["sharedstorage0"]
  }
}
```

The `registered: false` indicates you need to register your organization and node.

### Register Organization

Register your organization on the blockchain:

```bash
curl -X POST http://localhost:5000/api/v1/network/organizations/self?confirm=true \
  -H "Content-Type: application/json" \
  -d '{
    "name": "org1",
    "description": "Organization 1"
  }'
```

Expected response:
```json
{
  "id": "<uuid>",
  "message": "<message-id>",
  "type": "organization_confirmed",
  "namespace": "ff_system",
  "name": "org1",
  "description": "Organization 1",
  "created": "2024-01-01T00:00:00Z"
}
```

This creates an identity on the Fabric blockchain that other organizations can see and verify.

### Register Node

Register your FireFly node:

```bash
curl -X POST http://localhost:5000/api/v1/network/nodes/self?confirm=true \
  -H "Content-Type: application/json" \
  -d '{
    "name": "firefly-org1-node1",
    "description": "FireFly node for org1"
  }'
```

### Verify Registration

```bash
curl http://localhost:5000/api/v1/namespaces/default/status | jq '.org.registered, .node.registered'
```

Should return:
```json
true
true
```

### Test Multiparty Features

#### 1. Broadcast Message (Blockchain-Anchored)

Send a message to all parties in the network:

```bash
curl -X POST http://localhost:5000/api/v1/namespaces/default/messages/broadcast \
  -H "Content-Type: application/json" \
  -d '{
    "data": [{
      "value": "Hello from org1 - multiparty broadcast!"
    }]
  }'
```

Expected response:
```json
{
  "header": {
    "id": "<message-id>",
    "type": "broadcast",
    "author": "org1"
  },
  "hash": "<hash>",
  "state": "confirmed",
  "confirmed": "2024-01-01T00:00:00Z"
}
```

#### 2. View Blockchain Anchors (Pins)

Messages are batched and anchored on the Fabric blockchain:

```bash
# View batch pins
curl http://localhost:5000/api/v1/namespaces/default/pins | jq

# View blockchain events
curl http://localhost:5000/api/v1/namespaces/default/blockchainevents | jq
```

You should see BatchPin events recorded on Fabric with the message hashes.

#### 3. Check Messages

```bash
# View all messages
curl http://localhost:5000/api/v1/namespaces/default/messages | jq

# View specific message
curl http://localhost:5000/api/v1/namespaces/default/messages/<message-id> | jq
```

#### 4. Private Messaging (Multi-Org)

Once you have multiple organizations registered:

```bash
curl -X POST http://localhost:5000/api/v1/namespaces/default/messages/private \
  -H "Content-Type: application/json" \
  -d '{
    "group": {
      "members": [
        {"identity": "org1"},
        {"identity": "org2"}
      ]
    },
    "data": [{
      "value": "Private message from org1 to org2"
    }]
  }'
```

This sends:
- **Private payload** via DataExchange HTTPS (encrypted peer-to-peer)
- **Hash anchor** on Fabric blockchain (public proof of message existence)
- **IPFS reference** for large blobs (optional)

### Multiparty Architecture

```
Organization 1                          Organization 2
┌──────────────────────┐               ┌──────────────────────┐
│  FireFly Core        │               │  FireFly Core        │
│  ┌────────────────┐  │               │  ┌────────────────┐  │
│  │ Multiparty Mgr │  │               │  │ Multiparty Mgr │  │
│  └────────┬───────┘  │               │  └────────┬───────┘  │
│  ┌────────▼───────┐  │    Private    │  ┌────────▼───────┐  │
│  │ DataExchange   │◄─┼───HTTPS P2P──┼─►│ DataExchange   │  │
│  └────────────────┘  │   (Encrypted) │  └────────────────┘  │
└───────┬──────────────┘               └───────┬──────────────┘
        │                                      │
        │ gRPC                                 │ gRPC
        │                                      │
    ┌───▼──────────────────────────────────────▼───┐
    │         Fabric Network (Shared Channel)      │
    │  ┌──────────────────────────────────────┐    │
    │  │  FireFly Chaincode                   │    │
    │  │  - BatchPin (message anchors)        │    │
    │  │  - Identity Registry (orgs/nodes)    │    │
    │  └──────────────────────────────────────┘    │
    │                                               │
    │  Peer 1 (Org1)          Peer 2 (Org2)       │
    └───────────────────────────────────────────────┘
```

**Flow**:
1. **Broadcast Message**: FireFly → FabConnect → Fabric (BatchPin transaction)
2. **Private Message**: FireFly → DataExchange (HTTPS to peer) + Fabric (hash anchor)
3. **Event Processing**: Fabric → FabConnect (event listener) → FireFly (webhook)
4. **Identity Verification**: All orgs/nodes verified via Fabric chaincode

---

## Troubleshooting

### Multiparty Issues

#### Organization Not Registering

```bash
# Check FireFly logs for errors
kubectl logs firefly-0 | grep -i "organization\|multiparty"

# Common issues:
# - Chaincode not deployed: "chaincode not found on channel"
# - FabConnect not connected: Check fabconnect logs
# - Wrong channel/chaincode name in config
# - Fabric identity (fabconnectSigner) not enrolled
```

**Fix**: Verify chaincode is deployed and accessible:
```bash
kubectl exec -it firefly-fabconnect-0 -- sh
# Test chaincode query
curl -X POST http://localhost:3000/query \
  -H "Content-Type: application/json" \
  -d '{
    "headers": {"type": "QueryHeader"},
    "func": "PinBatch",
    "args": []
  }'
```

#### Messages Not Being Pinned

```bash
# Check for BatchPin events
curl http://localhost:5000/api/v1/namespaces/default/blockchainevents?type=batch_pin | jq

# Check FireFly operations
curl http://localhost:5000/api/v1/namespaces/default/operations | jq

# Check FabConnect event streams
kubectl logs firefly-fabconnect-0 | grep -i "batch\|pin"
```

**Common causes**:
- Chaincode not responding: Check peer logs
- FabConnect event listener not connected: Restart fabconnect pod
- Transaction timeouts: Increase `maxTXWaitTime` in fabconnect config

#### DataExchange Not Connecting

```bash
# Check DataExchange logs
kubectl logs firefly-dataexchange-0

# Check certificate status
kubectl get certificate

# Test DataExchange endpoint
kubectl port-forward svc/firefly-dx 3001:3001
curl http://localhost:3001/api/v1/status
```

**For multi-org**: Ensure DataExchange ingress is accessible:
```bash
# From org2, test org1's DataExchange
curl -k https://firefly-org1-dx.example.com/api/v1/status
```

#### Private Messages Not Received

**Checklist**:
1. ✅ Both orgs registered: `curl .../network/organizations`
2. ✅ Both nodes registered: `curl .../network/nodes`
3. ✅ DataExchange running on both sides
4. ✅ DataExchange endpoints accessible (check ingress/firewall)
5. ✅ TLS certificates valid (if using cert-manager)

```bash
# Check DataExchange peer connections
curl http://localhost:5000/api/v1/network/nodes | jq

# Test sending to specific node
curl -X POST http://localhost:5000/api/v1/namespaces/default/messages/private \
  -d '{
    "group": {
      "members": [{"identity": "org2"}]
    },
    "data": [{"value": "test"}]
  }'

# Check message status
curl http://localhost:5000/api/v1/namespaces/default/messages/<message-id> | jq '.state'
# Should be "confirmed" not "pending"
```

### FabConnect Can't Connect to Fabric

```bash
# Check FabConnect logs
kubectl logs firefly-fabconnect-0

# Common issues:
# - Peer URL incorrect or not accessible
# - TLS certificates missing/invalid in MSP secret
# - Firewall blocking gRPC ports

# Test connectivity from pod
kubectl exec -it firefly-fabconnect-0 -- /bin/sh
# Try: nc -zv peer0.org1.example.com 7051
```

### MSP Secret Issues

```bash
# Verify secret exists
kubectl get secret fabconnect-msp

# Check secret contents
kubectl describe secret fabconnect-msp

# Verify mount in pod
kubectl exec -it firefly-fabconnect-0 -- ls -la /etc/firefly/organizations
```

### FireFly Can't Connect to FabConnect

```bash
# Check service exists
kubectl get svc firefly-fabconnect

# Check FireFly can reach it
kubectl exec -it firefly-0 -- curl http://firefly-fabconnect:3000/status
```

### Enable Debug Logging

Update your values:
```yaml
fabconnect:
  log:
    level: "debug"
    fabricSDKDebug: true

config:
  debugEnabled: true
```

Then upgrade:
```bash
helm upgrade firefly ./charts/firefly -f my-fabric-values.yaml
```

---

## Deployment Modes

### Mode 1: FabConnect as Subchart (Recommended)

This is the approach documented above. FabConnect is deployed automatically as part of the FireFly deployment:

```yaml
# In firefly values.yaml
fabconnect:
  enabled: true
  fabric:
    peerUrl: "..."
    # ... other config
```

**Advantages**:
- Single Helm release manages everything
- Automatic service discovery
- Simplified deployment
- Consistent versioning

### Mode 2: Standalone FabConnect

Deploy FabConnect independently, then point FireFly to it:

```bash
# 1. Deploy FabConnect standalone
helm install fabconnect ./charts/firefly-fabconnect \
  --set fabric.peerUrl="grpcs://peer:7051" \
  --set msp.secretName="fabconnect-msp"

# 2. Deploy FireFly pointing to standalone FabConnect
helm install firefly ./charts/firefly \
  --set config.defaultBlockchainType="fabric" \
  --set config.fabconnectUrl="http://fabconnect:3000" \
  --set fabconnect.enabled=false
```

**Advantages**:
- FabConnect can be shared across multiple FireFly nodes
- Independent scaling and updates
- Easier to troubleshoot in isolation

---

## Multi-Organization Setup

For a complete multiparty network with multiple organizations, each organization deploys their own FireFly stack connected to the same Fabric channel.

### Requirements

1. **Shared Fabric Network**: All organizations must have peers on the same Fabric channel
2. **FireFly Chaincode**: Deployed and accessible to all organizations on the shared channel
3. **Network Connectivity**: DataExchange endpoints must be accessible between organizations
4. **DNS/Ingress**: Each organization's DataExchange needs a public endpoint for P2P messaging

### Organization 1 Deployment

```yaml
# org1-values.yaml
config:
  organizationName: "org1"
  defaultBlockchainType: "fabric"
  fabconnectSigner: "org1admin"
  multipartyEnabled: true

  postgresUrl: "postgres://postgres:password@postgresql-org1:5432/firefly?sslmode=disable"
  postgresAutomigrate: true

  ipfsApiUrl: "http://ipfs-org1:5001"
  ipfsGatewayUrl: "http://ipfs-org1:8080"

dataexchange:
  enabled: true
  certificate:
    enabled: true
    issuerRef:
      kind: ClusterIssuer
      name: letsencrypt-prod

  # Expose DataExchange for org2 to connect
  ingress:
    enabled: true
    className: "nginx"
    annotations:
      cert-manager.io/cluster-issuer: "letsencrypt-prod"
    hosts:
      - host: firefly-org1-dx.example.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: org1-dx-tls
        hosts:
          - firefly-org1-dx.example.com

fabconnect:
  enabled: true
  fabric:
    peerUrl: "grpcs://peer0.org1.example.com:7051"
    ordererUrl: "grpcs://orderer.example.com:7050"
    caUrl: "https://ca.org1.example.com:7054"
    organizationName: "org1.example.com"
    organizationMspId: "Org1MSP"
    channelName: "firefly"        # SAME channel for all orgs
    chaincodeName: "firefly"      # SAME chaincode for all orgs
    enrollId: "org1admin"
    enrollSecret: "password"
  msp:
    secretName: "org1-fabconnect-msp"

core:
  enabled: true

sandbox:
  enabled: true
```

Deploy org1:
```bash
helm install firefly-org1 ./charts/firefly \
  -f org1-values.yaml \
  --namespace org1 \
  --create-namespace
```

Register org1:
```bash
kubectl port-forward -n org1 svc/firefly-org1 5000:5000

# Register organization
curl -X POST http://localhost:5000/api/v1/network/organizations/self?confirm=true \
  -H "Content-Type: application/json" \
  -d '{"name": "org1", "description": "Organization 1"}'

# Register node
curl -X POST http://localhost:5000/api/v1/network/nodes/self?confirm=true \
  -H "Content-Type: application/json" \
  -d '{"name": "firefly-org1-node1", "description": "Org1 FireFly Node"}'
```

### Organization 2 Deployment

```yaml
# org2-values.yaml
config:
  organizationName: "org2"
  defaultBlockchainType: "fabric"
  fabconnectSigner: "org2admin"
  multipartyEnabled: true

  postgresUrl: "postgres://postgres:password@postgresql-org2:5432/firefly?sslmode=disable"
  postgresAutomigrate: true

  ipfsApiUrl: "http://ipfs-org2:5001"
  ipfsGatewayUrl: "http://ipfs-org2:8080"

dataexchange:
  enabled: true
  certificate:
    enabled: true
    issuerRef:
      kind: ClusterIssuer
      name: letsencrypt-prod

  # Expose DataExchange for org1 to connect
  ingress:
    enabled: true
    className: "nginx"
    annotations:
      cert-manager.io/cluster-issuer: "letsencrypt-prod"
    hosts:
      - host: firefly-org2-dx.example.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: org2-dx-tls
        hosts:
          - firefly-org2-dx.example.com

fabconnect:
  enabled: true
  fabric:
    peerUrl: "grpcs://peer0.org2.example.com:7051"
    ordererUrl: "grpcs://orderer.example.com:7050"  # Can be same orderer
    caUrl: "https://ca.org2.example.com:7054"
    organizationName: "org2.example.com"
    organizationMspId: "Org2MSP"
    channelName: "firefly"        # SAME channel as org1
    chaincodeName: "firefly"      # SAME chaincode as org1
    enrollId: "org2admin"
    enrollSecret: "password"
  msp:
    secretName: "org2-fabconnect-msp"

core:
  enabled: true

sandbox:
  enabled: true
```

Deploy org2 (can be in a different cluster):
```bash
helm install firefly-org2 ./charts/firefly \
  -f org2-values.yaml \
  --namespace org2 \
  --create-namespace
```

Register org2:
```bash
kubectl port-forward -n org2 svc/firefly-org2 5001:5000

# Register organization
curl -X POST http://localhost:5001/api/v1/network/organizations/self?confirm=true \
  -H "Content-Type: application/json" \
  -d '{"name": "org2", "description": "Organization 2"}'

# Register node
curl -X POST http://localhost:5001/api/v1/network/nodes/self?confirm=true \
  -H "Content-Type: application/json" \
  -d '{"name": "firefly-org2-node1", "description": "Org2 FireFly Node"}'
```

### Test Multi-Org Communication

From org1, send a private message to org2:

```bash
kubectl port-forward -n org1 svc/firefly-org1 5000:5000

curl -X POST http://localhost:5000/api/v1/namespaces/default/messages/private \
  -H "Content-Type: application/json" \
  -d '{
    "group": {
      "members": [
        {"identity": "org1"},
        {"identity": "org2"}
      ]
    },
    "data": [{
      "value": "Private message from org1 to org2"
    }],
    "header": {
      "tag": "test-message"
    }
  }'
```

Check on org2:
```bash
kubectl port-forward -n org2 svc/firefly-org2 5001:5000

# View private messages
curl http://localhost:5001/api/v1/namespaces/default/messages/private | jq

# Should see the message from org1
```

### Verify Multi-Org Network

```bash
# From org1 - view all organizations
curl http://localhost:5000/api/v1/network/organizations | jq

# Should show both org1 and org2

# View all nodes
curl http://localhost:5000/api/v1/network/nodes | jq

# Should show nodes from both organizations
```

### Multi-Org Architecture

```
┌─────────────────────────────────┐         ┌─────────────────────────────────┐
│     Organization 1 (Cluster 1)  │         │     Organization 2 (Cluster 2)  │
│                                  │         │                                  │
│  ┌──────────────┐                │         │  ┌──────────────┐                │
│  │ FireFly Org1 │                │         │  │ FireFly Org2 │                │
│  └───────┬──────┘                │         │  └───────┬──────┘                │
│          │                       │         │          │                       │
│  ┌───────▼──────────┐            │         │  ┌───────▼──────────┐            │
│  │ DataExchange Org1│◄───────────┼─────────┼─►│ DataExchange Org2│            │
│  │ (Public HTTPS)   │  Private   │         │  │ (Public HTTPS)   │            │
│  └──────────────────┘  Messages  │         │  └──────────────────┘            │
│                                  │         │                                  │
│  ┌──────────────────┐            │         │  ┌──────────────────┐            │
│  │ FabConnect Org1  │            │         │  │ FabConnect Org2  │            │
│  └────────┬─────────┘            │         │  └────────┬─────────┘            │
│           │                      │         │           │                      │
└───────────┼──────────────────────┘         └───────────┼──────────────────────┘
            │                                            │
            │ gRPC                                       │ gRPC
            │                                            │
        ┌───▼────────────────────────────────────────────▼───┐
        │        Shared Hyperledger Fabric Network           │
        │                                                     │
        │  Channel: "firefly"                                │
        │  Chaincode: "firefly" (BatchPin, Identity)        │
        │                                                     │
        │  ┌──────────────┐         ┌──────────────┐        │
        │  │ Peer 0 Org1  │         │ Peer 0 Org2  │        │
        │  └──────────────┘         └──────────────┘        │
        │                                                     │
        │  ┌──────────────────────────────────────┐         │
        │  │         Orderer Service               │         │
        │  └──────────────────────────────────────┘         │
        └─────────────────────────────────────────────────────┘
```

**Key Points**:
- Each org has their own FireFly, FabConnect, PostgreSQL, IPFS
- DataExchange endpoints must be publicly accessible (Ingress with TLS)
- All orgs connect to the same Fabric channel with same chaincode
- Private messages go directly peer-to-peer via DataExchange
- Public/broadcast messages and pins go through Fabric blockchain

---

## Production Considerations

### Security Hardening

1. **Use TLS for all connections**:
   ```yaml
   dataexchange:
     certificate:
       enabled: true
       issuerRef:
         kind: ClusterIssuer
         name: letsencrypt-prod

   ingress:
     enabled: true
     tls:
       - secretName: firefly-tls
         hosts:
           - firefly.example.com
   ```

2. **Enable RBAC**:
   ```yaml
   serviceAccount:
     create: true
     name: firefly

   rbac:
     create: true
   ```

3. **Use secrets management**:
   ```yaml
   # Use external secrets operator
   config:
     postgresUrl: ""

   externalSecrets:
     enabled: true
     secretStore: aws-secrets-manager
   ```

### High Availability

1. **Run multiple replicas** (requires shared storage or leader election):
   ```yaml
   core:
     replicaCount: 3

   fabconnect:
     replicaCount: 2
   ```

2. **Configure pod disruption budgets**:
   ```yaml
   podDisruptionBudget:
     enabled: true
     minAvailable: 1
   ```

3. **Use external PostgreSQL and IPFS**:
   ```yaml
   config:
     postgresUrl: "postgres://user:pass@external-postgres:5432/firefly"
     ipfsApiUrl: "http://external-ipfs:5001"
   ```

### Monitoring

1. **Enable Prometheus metrics**:
   ```yaml
   config:
     metricsEnabled: true

   serviceMonitor:
     enabled: true
   ```

2. **Configure alerting**:
   - Transaction failures
   - Fabric connection issues
   - Event listener lag
   - Pod restarts

### Backup and Recovery

1. **Backup PostgreSQL** database regularly
2. **Backup FabConnect persistent volumes** (receipts and events)
3. **Document Fabric network configuration**
4. **Store MSP credentials securely** (e.g., HashiCorp Vault)

---

## Next Steps

1. **Complete Multi-Org Setup**: Follow the "Multi-Organization Setup" section above to add more organizations
2. **Deploy Custom Smart Contracts**: Use FireFly's contract API to interact with your own chaincode beyond the FireFly system chaincode
3. **Set up Monitoring**: Enable Prometheus metrics and Grafana dashboards for production observability
4. **Integrate with Applications**: Use FireFly's REST API, WebSocket subscriptions, or SDKs (Node.js, Go, Java) to build applications
5. **Configure Webhooks**: Set up webhooks to receive event notifications from FireFly for real-time processing
6. **Implement Data Schemas**: Define datatypes and use FireFly's data validation features
7. **Explore Token APIs**: While primarily for Ethereum, explore token patterns that could be implemented on Fabric

---

## Reference Documentation

- **FabConnect Chart README**: `charts/firefly-fabconnect/README.md`
- **FabConnect Deployment Guide**: `charts/firefly-fabconnect/DEPLOYMENT-GUIDE.md`
- **Example Fabric Values**: `values/fabric-values.yaml`
- **Main FireFly Chart**: `charts/firefly/values.yaml`
- **Architecture Documentation**: `CLAUDE.md`
- **FireFly Documentation**: https://hyperledger.github.io/firefly/
- **FabConnect Documentation**: https://github.com/hyperledger/firefly-fabconnect

---

## Support and Contributing

For issues, questions, or contributions:
- GitHub Issues: https://github.com/hyperledger/firefly-helm-charts/issues
- Discord: https://discord.gg/hyperledger
- Mailing List: https://lists.hyperledger.org/g/firefly

---

## License

Apache-2.0
