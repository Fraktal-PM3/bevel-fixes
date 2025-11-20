# FireFly Multiparty Mode with FabConnect - Changes Summary

## Overview

This document summarizes the changes made to enable full multiparty mode support for FireFly when using Hyperledger Fabric with FabConnect.

## Changes Made

### 1. FabConnect Subchart Auto-Discovery

**File Modified**: `charts/firefly/templates/_helpers.tpl`

**Changes**:
- Updated the fabric plugin configuration to support `fabconnect.enabled` in addition to `config.fabconnectUrl`
- Added automatic service URL discovery when FabConnect is deployed as a subchart
- Auto-configure channel and chaincode from subchart values when `fabconnect.enabled: true`

**Before**:
```yaml
{{- if .Values.config.fabconnectUrl }}
  - name: fabric0
    type: fabric
    fabric:
      fabconnect:
        url: {{ tpl .Values.config.fabconnectUrl . }}
```

**After**:
```yaml
{{- if or .Values.config.fabconnectUrl .Values.fabconnect.enabled }}
  - name: fabric0
    type: fabric
    fabric:
      fabconnect:
        {{- if .Values.fabconnect.enabled }}
        url: http://{{ include "firefly.fullname" . }}-fabconnect.{{ .Release.Namespace }}.svc:{{ .Values.fabconnect.service.port }}
        {{- else }}
        url: {{ tpl .Values.config.fabconnectUrl . }}
        {{- end }}
        {{- if .Values.fabconnect.enabled }}
        channel: {{ .Values.fabconnect.fabric.channelName | quote }}
        chaincode: {{ .Values.fabconnect.fabric.chaincodeName | quote }}
        {{- else }}
        channel: {{ .Values.config.fabconnectChannel | quote }}
        chaincode: {{ .Values.config.fireflyChaincode | quote }}
        {{- end }}
```

### 2. Multiparty Namespace Configuration

**File Modified**: `charts/firefly/templates/_helpers.tpl`

**Changes**:
- Updated namespace plugin configuration to check for `fabconnect.enabled`
- Added `fabric0` plugin to default namespace when FabConnect subchart is enabled
- Configured proper `defaultKey` (fabconnectSigner) when using Fabric

**Lines Modified**: 433-444

### 3. Multiparty Contract Configuration

**File Modified**: `charts/firefly/templates/_helpers.tpl`

**Changes**:
- Updated multiparty contract configuration to support FabConnect subchart
- Auto-configure chaincode location from subchart values
- Support both subchart and external FabConnect deployments

**Lines Modified**: 461-494

### 4. Documentation

**Updated Files**:

1. **`FIREFLY-FABCONNECT-DEPLOYMENT-GUIDE.md`** - Integrated complete multiparty mode documentation
   - Added "Enabling Multiparty Mode" section with:
     - Prerequisites and chaincode deployment
     - Organization and node registration steps
     - Testing multiparty features (broadcast, private messages)
     - Multiparty architecture diagram
   - Enhanced "Multi-Organization Setup" section with:
     - Complete deployment examples for org1 and org2
     - DataExchange ingress configuration
     - Multi-org testing procedures
     - Architecture diagram showing P2P and blockchain flows
   - Added multiparty troubleshooting section
   - Updated "Next Steps" with comprehensive guidance

2. **`MULTIPARTY-MODE-CHANGES.md`** - This file documenting all changes

## How to Use

### Simple Deployment with Auto-Discovery

Now you can deploy FireFly with FabConnect and multiparty mode using a simplified configuration:

```yaml
config:
  organizationName: "org1"
  defaultBlockchainType: "fabric"
  fabconnectSigner: "admin"
  multipartyEnabled: true

  # Database
  postgresUrl: "postgres://postgres:password@postgresql:5432/firefly?sslmode=disable"
  postgresAutomigrate: true

  # IPFS
  ipfsApiUrl: "http://ipfs:5001"
  ipfsGatewayUrl: "http://ipfs:8080"

# FabConnect auto-discovered
fabconnect:
  enabled: true
  fabric:
    peerUrl: "grpcs://peer0.org1.example.com:7051"
    ordererUrl: "grpcs://orderer.example.com:7050"
    organizationName: "org1.example.com"
    organizationMspId: "Org1MSP"
    channelName: "firefly"
    chaincodeName: "firefly"
    enrollId: "admin"
    enrollSecret: "adminpw"
  msp:
    secretName: "fabconnect-msp"

# DataExchange for P2P messaging
dataexchange:
  enabled: true
  certificate:
    enabled: true
```

**Key Improvements**:
- No need to specify `fabconnectUrl` - automatically discovered
- No need to specify `fabconnectChannel` and `fabconnectChaincode` at top level - taken from subchart
- Cleaner configuration with less duplication

### What Gets Auto-Configured

When `fabconnect.enabled: true`:

1. **FabConnect URL**:
   ```
   http://<release-name>-fabconnect.<namespace>.svc:3000
   ```

2. **Channel & Chaincode**:
   - Uses `fabconnect.fabric.channelName`
   - Uses `fabconnect.fabric.chaincodeName`

3. **Blockchain Plugin**: `fabric0` automatically added to namespace

4. **Multiparty Contract**: Chaincode location automatically configured

## Multiparty Mode Features

With these changes, you get full multiparty functionality:

### 1. Organization & Node Registry
- Register organizations on the blockchain
- Register nodes for peer discovery
- Decentralized identity management

### 2. Broadcast Messaging
```bash
curl -X POST http://localhost:5000/api/v1/namespaces/default/messages/broadcast \
  -H "Content-Type: application/json" \
  -d '{
    "data": [{"value": "Hello everyone!"}]
  }'
```

### 3. Private Messaging
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
    "data": [{"value": "Private message"}]
  }'
```

### 4. Blockchain Anchoring
- Message batches automatically pinned to Fabric blockchain
- Provides consensus and ordering across organizations
- View pins: `curl http://localhost:5000/api/v1/namespaces/default/pins`

### 5. Event-Driven Architecture
- Automatic event processing from Fabric chaincode
- Webhook notifications to applications
- Real-time updates via WebSocket

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    FireFly Core                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │ Multiparty   │  │  DataExchange│  │    IPFS      │ │
│  │   Manager    │  │   (P2P Msgs) │  │  (Storage)   │ │
│  └───────┬──────┘  └──────┬───────┘  └──────────────┘ │
│          │                 │                            │
└──────────┼─────────────────┼────────────────────────────┘
           │                 │
           │                 │ Private data
           │                 │ via HTTPS
           │                 ▼
    ┌──────▼────────┐   ┌────────────┐
    │  FabConnect   │   │   Peer 2   │
    │  (Connector)  │   │ DataExchange│
    └───────┬───────┘   └────────────┘
            │
            │ gRPC
            ▼
    ┌───────────────────────────────┐
    │   Hyperledger Fabric Network  │
    │                               │
    │  ┌─────────┐    ┌─────────┐  │
    │  │ Peer 1  │    │ Peer 2  │  │
    │  └─────────┘    └─────────┘  │
    │                               │
    │  Channel: firefly             │
    │  Chaincode: firefly           │
    │  (BatchPin, Identity)         │
    └───────────────────────────────┘
```

## Testing

### Verify Configuration Renders Correctly

```bash
cd charts/firefly
helm dep update

helm template test . \
  -f ../../values/fabric-values.yaml \
  --debug \
  | grep -A 20 "name: fabric0"
```

Expected output should show fabric0 plugin with auto-discovered URL.

### Test Deployment

```bash
# Deploy with multiparty enabled
helm install firefly ./charts/firefly \
  -f values/fabric-values.yaml \
  --namespace test \
  --create-namespace

# Check pods
kubectl get pods -n test

# Port forward
kubectl port-forward -n test svc/firefly 5000:5000

# Check status
curl http://localhost:5000/api/v1/namespaces/default/status | jq

# Register org and node
curl -X POST http://localhost:5000/api/v1/network/organizations/self?confirm=true \
  -H "Content-Type: application/json" \
  -d '{"name": "org1"}'

curl -X POST http://localhost:5000/api/v1/network/nodes/self?confirm=true \
  -H "Content-Type: application/json" \
  -d '{"name": "firefly-org1"}'

# Verify
curl http://localhost:5000/api/v1/namespaces/default/status | jq '.org.registered, .node.registered'
# Should return: true, true
```

## Backward Compatibility

These changes are fully backward compatible:

- **Existing deployments** using `config.fabconnectUrl` continue to work
- **New deployments** can use `fabconnect.enabled: true` for simpler config
- **Both modes** support multiparty functionality

## Migration Guide

### From External FabConnect to Subchart

**Old Configuration**:
```yaml
config:
  fabconnectUrl: "http://external-fabconnect:3000"
  fabconnectChannel: "firefly"
  fireflyChaincode: "firefly"
  multipartyEnabled: true
```

**New Configuration**:
```yaml
config:
  multipartyEnabled: true

fabconnect:
  enabled: true
  fabric:
    channelName: "firefly"
    chaincodeName: "firefly"
    # ... other fabric config
```

**Migration Steps**:
1. Update values file to new format
2. Run `helm dep update charts/firefly`
3. Run `helm upgrade firefly ./charts/firefly -f new-values.yaml`
4. Verify FabConnect pod is running
5. Confirm FireFly reconnects (check logs)

## Troubleshooting

### FabConnect URL Not Resolving

**Symptom**: FireFly logs show "connection refused" to FabConnect

**Check**:
```bash
# Verify fabconnect service exists
kubectl get svc | grep fabconnect

# Check if subchart is enabled
helm get values firefly | grep -A 5 "fabconnect:"

# Test DNS resolution from FireFly pod
kubectl exec -it firefly-0 -- nslookup firefly-fabconnect
```

**Fix**: Ensure `fabconnect.enabled: true` and subchart is deployed

### Multiparty Not Enabled

**Symptom**: `/api/v1/network/organizations/self` returns 404

**Check**:
```bash
# Check if multiparty is enabled in config
kubectl get secret firefly-config -o yaml | \
  yq '.data."firefly.core"' | base64 -d | grep -A 5 "multiparty:"

# Should show:
# multiparty:
#   enabled: true
```

**Fix**: Set `config.multipartyEnabled: true` and upgrade

### Wrong Channel/Chaincode

**Symptom**: FabConnect logs show "chaincode not found"

**Check**:
```bash
# Check FireFly config
kubectl exec -it firefly-0 -- cat /etc/firefly/firefly.core | \
  grep -A 5 "fabric:"

# Should match your deployed chaincode
```

**Fix**: Update `fabconnect.fabric.channelName` and `chaincodeName` to match your deployment

## Additional Resources

- **Main Deployment Guide**: [FIREFLY-FABCONNECT-DEPLOYMENT-GUIDE.md](FIREFLY-FABCONNECT-DEPLOYMENT-GUIDE.md) - **Now includes complete multiparty setup**
- **FabConnect Chart**: [charts/firefly-fabconnect/README.md](charts/firefly-fabconnect/README.md)
- **FabConnect Deployment**: [charts/firefly-fabconnect/DEPLOYMENT-GUIDE.md](charts/firefly-fabconnect/DEPLOYMENT-GUIDE.md)
- **FireFly Docs**: https://hyperledger.github.io/firefly/
- **FabConnect Docs**: https://github.com/hyperledger/firefly-fabconnect

## License

Apache-2.0
