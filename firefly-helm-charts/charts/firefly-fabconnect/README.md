# FireFly FabConnect Helm Chart

A production-ready Helm chart for deploying Hyperledger FireFly FabConnect on Kubernetes.

## Overview

FabConnect is a Hyperledger Fabric blockchain connector that provides REST API access to Fabric networks. It enables FireFly to interact with Hyperledger Fabric by:

- Managing transaction submission and receipts
- Listening to chaincode events
- Handling identity and MSP management
- Providing webhook notifications for events

## Prerequisites

- Kubernetes 1.18+
- Helm 3.7+
- Running Hyperledger Fabric network
- Fabric MSP (Membership Service Provider) credentials
- Persistent storage provisioner (for transaction receipts and event streams)

## Installation

### Quick Start

```bash
# Add the repository (if published)
helm repo add firefly https://hyperledger.github.io/firefly-helm-charts
helm repo update

# Install FabConnect
helm install fabconnect firefly/firefly-fabconnect \
  --set fabric.peerUrl="grpcs://peer0.org1.example.com:7051" \
  --set fabric.ordererUrl="grpcs://orderer.example.com:7050" \
  --set fabric.organizationName="org1.example.com" \
  --set fabric.organizationMspId="Org1MSP" \
  --set fabric.channelName="mychannel" \
  --set msp.secretName="fabconnect-msp"
```

### Installing from Local Chart

```bash
cd firefly-helm-charts/charts/firefly-fabconnect
helm install fabconnect . -f values.yaml
```

## Configuration

### Fabric Network Configuration

The most critical configuration is connecting to your Hyperledger Fabric network:

```yaml
fabric:
  peerUrl: "grpcs://peer0.org1.example.com:7051"
  ordererUrl: "grpcs://orderer.example.com:7050"
  caUrl: "https://ca.org1.example.com:7054"
  organizationName: "org1.example.com"
  organizationMspId: "Org1MSP"
  channelName: "default-channel"
  chaincodeName: "firefly"
  enrollId: "admin"
  enrollSecret: "adminpw"
```

### MSP Secret

FabConnect requires Fabric MSP credentials to be provided as a Kubernetes Secret. Create the secret before installing:

```bash
# Create MSP secret from directory structure
kubectl create secret generic fabconnect-msp \
  --from-file=path/to/msp/directory
```

The MSP directory should contain:
```
msp/
├── peerOrganizations/
│   └── org1.example.com/
│       ├── msp/
│       │   ├── cacerts/
│       │   ├── tlscacerts/
│       │   └── ...
│       ├── peers/
│       │   └── peer0.org1.example.com/
│       │       └── tls/
│       └── users/
│           └── Admin@org1.example.com/
│               └── msp/
└── ordererOrganizations/
    └── ...
```

Then reference it in values:

```yaml
msp:
  secretName: "fabconnect-msp"
  mountPath: "/etc/firefly/organizations"
```

### Connection Profile

FabConnect uses a Fabric Connection Profile (CCP) to connect to the network. This chart can auto-generate one:

```yaml
connectionProfile:
  autoGenerate: true  # Uses fabric.* values to generate CCP
```

Or provide a custom one:

```yaml
connectionProfile:
  autoGenerate: false
  customProfile: |
    version: 1.1.0
    client:
      organization: org1.example.com
      # ... full connection profile YAML
```

### Service Configuration

Configure the Kubernetes Service:

```yaml
service:
  type: ClusterIP  # ClusterIP, NodePort, or LoadBalancer
  port: 3000
  annotations: {}
```

### Ingress Configuration

Enable external access via Ingress:

```yaml
ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: fabconnect.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: fabconnect-tls
      hosts:
        - fabconnect.example.com
```

### Persistent Storage

FabConnect requires persistent storage for transaction receipts and event streams:

```yaml
persistentVolume:
  accessModes:
    - ReadWriteOnce
  size: 5Gi
  storageClass: "gp2"  # AWS EBS example
  annotations: {}
```

### Resource Limits

Configure resource requests and limits:

```yaml
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi
```

### Security Context

Production-ready security contexts are enabled by default:

```yaml
podSecurityContext:
  fsGroup: 1001
  runAsUser: 1001
  runAsNonRoot: true

securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 1001
```

### Health Checks

Configure liveness and readiness probes:

```yaml
healthcheck:
  enabled: true
  path: "/status"
  initialDelaySeconds: 15
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3

readinessProbe:
  enabled: true
  path: "/status"
  initialDelaySeconds: 10
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3
```

### Advanced Configuration

Override the entire FabConnect configuration:

```yaml
config:
  templateOverride: |
    maxinflight: 20
    maxtxwaittime: 120
    # ... complete fabconnect.yaml
```

## Integration with FireFly

This chart can be deployed standalone or as a dependency of the main `firefly` chart:

### As a Dependency

In the main FireFly chart's `Chart.yaml`:

```yaml
dependencies:
  - name: firefly-fabconnect
    repository: "file://../firefly-fabconnect"
    alias: fabconnect
    condition: fabconnect.enabled
    version: "0.1.0"
```

In the main FireFly `values.yaml`:

```yaml
fabconnect:
  enabled: true
  fabric:
    peerUrl: "grpcs://peer0.org1.example.com:7051"
    # ... other Fabric configuration
```

### Standalone Deployment

Deploy FabConnect independently:

```bash
helm install fabconnect ./charts/firefly-fabconnect -f custom-values.yaml
```

Then configure FireFly to use it:

```yaml
config:
  fabconnectUrl: "http://fabconnect:3000"
  fabconnectChannel: "mychannel"
  fabconnectChaincode: "firefly"
  fabconnectSigner: "admin"
```

## Upgrade

```bash
helm upgrade fabconnect ./charts/firefly-fabconnect -f values.yaml
```

The chart uses a StatefulSet with RollingUpdate strategy, ensuring zero-downtime upgrades while maintaining persistent storage.

## Uninstall

```bash
helm uninstall fabconnect
```

**Note**: Persistent Volume Claims are not automatically deleted. Delete them manually if needed:

```bash
kubectl delete pvc -l app.kubernetes.io/name=firefly-fabconnect
```

## Troubleshooting

### Check Pod Status

```bash
kubectl get pods -l app.kubernetes.io/name=firefly-fabconnect
kubectl logs -l app.kubernetes.io/name=firefly-fabconnect
```

### Verify Configuration

```bash
# Check config secret
kubectl get secret fabconnect-config -o yaml

# Check connection profile
kubectl get configmap fabconnect-ccp -o yaml

# Check MSP mount
kubectl exec -it fabconnect-0 -- ls -la /etc/firefly/organizations
```

### Common Issues

1. **MSP not found**: Ensure the MSP secret exists and contains the correct directory structure
2. **Peer connection failed**: Verify peer URLs are accessible from the cluster
3. **Certificate errors**: Check TLS certificates in the MSP are valid
4. **Persistent volume issues**: Verify storage class exists and can provision volumes

### Enable Debug Logging

```yaml
log:
  level: "debug"
  fabricSDKDebug: true
```

## Values Reference

See [values.yaml](./values.yaml) for complete configuration options.

## License

Apache-2.0

## Maintainers

- Hayden Fuss <hayden.fuss@kaleido.io>
- Peter Broadhurst <peter.broadhurst@kaleido.io>
- Cari Albritton <cari.albritton@kaleido.io>
