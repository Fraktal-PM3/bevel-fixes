# FabConnect Deployment Guide

This guide walks through deploying Hyperledger FabConnect to connect FireFly with a Hyperledger Fabric network.

## Prerequisites

Before deploying FabConnect, ensure you have:

1. **Kubernetes cluster** (1.18+) with kubectl configured
2. **Helm** (3.7+) installed
3. **Running Hyperledger Fabric network** with:
   - At least one peer accessible via gRPC
   - At least one orderer accessible via gRPC
   - A Fabric CA for enrollment (optional but recommended)
   - A channel created with chaincode deployed

4. **Fabric MSP credentials** for your organization containing:
   - Certificate Authority (CA) certificates
   - TLS certificates
   - User certificates and private keys
   - Organization MSP structure

5. **Persistent volume provisioner** in your cluster (for receipts and events storage)

## Step 1: Prepare MSP Credentials

FabConnect requires Fabric MSP credentials to be available as a Kubernetes Secret. The MSP directory should follow the standard Fabric structure:

```
msp/
├── peerOrganizations/
│   └── org1.example.com/
│       ├── msp/
│       │   ├── cacerts/
│       │   │   └── ca.crt
│       │   └── tlscacerts/
│       │       └── ca.crt
│       ├── peers/
│       │   └── peer0.org1.example.com/
│       │       └── tls/
│       │           └── tlscacerts/
│       │               └── tls-ca-org1.example.com.pem
│       └── users/
│           └── Admin@org1.example.com/
│               └── msp/
│                   ├── signcerts/
│                   │   └── cert.pem
│                   └── keystore/
│                       └── key.pem
└── ordererOrganizations/
    └── orderer/
        └── orderers/
            └── orderer0.orderer/
                └── tls/
                    └── tlscacerts/
                        └── tls-ca-orderer.pem
```

### Create the MSP Secret

```bash
# Navigate to your MSP directory
cd /path/to/fabric/msp

# Create the secret
kubectl create secret generic fabconnect-msp \
  --from-file=. \
  --namespace=default

# Verify the secret was created
kubectl get secret fabconnect-msp -o yaml
```

## Step 2: Configure values.yaml

Create a custom values file for your deployment:

```yaml
# custom-values.yaml

# Fabric network configuration
fabric:
  # Update with your actual peer endpoint
  peerUrl: "grpcs://peer0.org1.example.com:7051"

  # Update with your actual orderer endpoint
  ordererUrl: "grpcs://orderer.example.com:7050"

  # Update with your CA endpoint (for enrollment)
  caUrl: "https://ca.org1.example.com:7054"

  # Your organization details
  organizationName: "org1.example.com"
  organizationMspId: "Org1MSP"

  # Channel and chaincode to interact with
  channelName: "mychannel"
  chaincodeName: "firefly"

  # CA enrollment credentials
  enrollId: "admin"
  enrollSecret: "adminpw"

# Reference the MSP secret created in Step 1
msp:
  secretName: "fabconnect-msp"

# Service configuration
service:
  type: ClusterIP
  port: 3000

# Resource allocation (adjust based on your needs)
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi

# Persistent storage for receipts and events
persistentVolume:
  accessModes:
    - ReadWriteOnce
  size: 5Gi
  storageClass: "gp2"  # Update with your storage class

# Enable ingress if external access is needed
ingress:
  enabled: false
  # Uncomment and configure if needed:
  # className: "nginx"
  # hosts:
  #   - host: fabconnect.example.com
  #     paths:
  #       - path: /
  #         pathType: Prefix
```

## Step 3: Deploy FabConnect

### Standalone Deployment

Deploy FabConnect as a standalone service:

```bash
# Install the chart
helm install fabconnect ./charts/firefly-fabconnect \
  -f custom-values.yaml \
  --namespace default

# Check deployment status
kubectl get pods -l app.kubernetes.io/name=firefly-fabconnect
kubectl logs -l app.kubernetes.io/name=firefly-fabconnect -f
```

### As Part of FireFly Stack

Deploy FabConnect as a dependency of the main FireFly chart:

```bash
# Create a FireFly values file with fabconnect enabled
cat > firefly-fabric-values.yaml <<EOF
config:
  defaultBlockchainType: "fabric"
  fabconnectChannel: "mychannel"
  fabconnectChaincode: "firefly"
  fabconnectSigner: "admin"

  postgresUrl: "postgres://user:pass@postgresql:5432/firefly?sslmode=disable"
  postgresAutomigrate: true

fabconnect:
  enabled: true
  fabric:
    peerUrl: "grpcs://peer0.org1.example.com:7051"
    ordererUrl: "grpcs://orderer.example.com:7050"
    caUrl: "https://ca.org1.example.com:7054"
    organizationName: "org1.example.com"
    organizationMspId: "Org1MSP"
    channelName: "mychannel"
    chaincodeName: "firefly"
  msp:
    secretName: "fabconnect-msp"
EOF

# Deploy FireFly with FabConnect
helm install firefly ./charts/firefly \
  -f firefly-fabric-values.yaml \
  --namespace default
```

## Step 4: Verify Deployment

### Check Pod Status

```bash
# Check if FabConnect pod is running
kubectl get pods -l app.kubernetes.io/component=fabconnect

# Expected output:
# NAME                    READY   STATUS    RESTARTS   AGE
# fabconnect-0            1/1     Running   0          2m
```

### Check Logs

```bash
# View FabConnect logs
kubectl logs -l app.kubernetes.io/component=fabconnect -f

# Look for successful startup messages:
# - "HTTP server listening on port 3000"
# - "Connected to Fabric network"
```

### Test Health Endpoint

```bash
# Port-forward to access FabConnect
kubectl port-forward svc/fabconnect 3000:3000

# In another terminal, test the health endpoint
curl http://localhost:3000/status

# Expected response:
# {"status":"ok"}
```

### Test Fabric Connectivity

```bash
# Query chaincode through FabConnect
curl -X POST http://localhost:3000/query \
  -H "Content-Type: application/json" \
  -d '{
    "headers": {
      "type": "Query",
      "channelId": "mychannel",
      "signer": "admin",
      "chaincodeid": "firefly"
    },
    "func": "queryAllAssets",
    "args": []
  }'
```

## Step 5: Configure FireFly to Use FabConnect

If you deployed FabConnect standalone, configure FireFly to connect to it:

```yaml
# FireFly config
config:
  defaultBlockchainType: "fabric"
  fabconnectUrl: "http://fabconnect:3000"
  fabconnectChannel: "mychannel"
  fabconnectChaincode: "firefly"
  fabconnectSigner: "admin"
```

## Troubleshooting

### Pod Not Starting

**Check MSP secret:**
```bash
kubectl get secret fabconnect-msp
kubectl describe secret fabconnect-msp
```

**Check pod events:**
```bash
kubectl describe pod fabconnect-0
```

**Common issues:**
- MSP secret not found: Ensure the secret exists in the correct namespace
- Volume mount errors: Verify persistent volume can be provisioned

### Connection to Fabric Failed

**Check logs for connection errors:**
```bash
kubectl logs fabconnect-0 | grep -i error
```

**Common issues:**
- Certificate errors: Verify TLS certificates are valid and match the peer/orderer
- Network connectivity: Ensure peer/orderer URLs are accessible from the cluster
- MSP path errors: Check the MSP directory structure matches expectations

**Test connectivity from pod:**
```bash
kubectl exec -it fabconnect-0 -- sh
# Inside the pod:
ls -la /etc/firefly/organizations
curl -k https://peer0.org1.example.com:7051
```

### Health Check Failures

**Check the /status endpoint:**
```bash
kubectl exec -it fabconnect-0 -- curl http://localhost:3000/status
```

**Adjust probe timings if needed:**
```yaml
healthcheck:
  initialDelaySeconds: 30  # Increase if startup is slow
  periodSeconds: 10
  failureThreshold: 5
```

### Transaction Failures

**Check receipt storage:**
```bash
kubectl exec -it fabconnect-0 -- ls -la /fabconnect/receipts
```

**Check event storage:**
```bash
kubectl exec -it fabconnect-0 -- ls -la /fabconnect/events
```

**Enable debug logging:**
```yaml
log:
  level: "debug"
  fabricSDKDebug: true
```

## Upgrade

To upgrade FabConnect:

```bash
# Update your values file as needed
vim custom-values.yaml

# Upgrade the release
helm upgrade fabconnect ./charts/firefly-fabconnect \
  -f custom-values.yaml

# Check rollout status
kubectl rollout status statefulset/fabconnect
```

## Uninstall

To remove FabConnect:

```bash
# Uninstall the release
helm uninstall fabconnect

# Delete persistent volume claims (if desired)
kubectl delete pvc -l app.kubernetes.io/name=firefly-fabconnect

# Delete MSP secret (if desired)
kubectl delete secret fabconnect-msp
```

## Production Considerations

### Security

1. **Use TLS everywhere**: Ensure all Fabric endpoints use TLS
2. **Secure MSP credentials**: Store MSP in secure secret management (e.g., Vault)
3. **Network policies**: Restrict pod-to-pod communication
4. **RBAC**: Use service accounts with minimal permissions

### High Availability

1. **Multiple replicas**: Currently FabConnect runs as a StatefulSet with 1 replica
2. **Persistent storage**: Use reliable storage class (e.g., AWS EBS, Azure Disk)
3. **Backup receipts**: Regularly backup the receipts database
4. **Monitor events**: Set up monitoring for event processing

### Performance

1. **Resource tuning**: Adjust CPU/memory based on transaction volume
2. **Concurrent operations**: Tune `maxInFlight` and `sendConcurrency`
3. **Storage performance**: Use SSD-backed storage for receipts/events

### Monitoring

1. **Prometheus metrics**: FabConnect exposes metrics (if enabled)
2. **Log aggregation**: Collect logs in centralized logging system
3. **Alerting**: Set up alerts for connection failures and transaction errors

## Next Steps

- Deploy the FireFly chaincode to your Fabric network
- Configure multiparty mode in FireFly
- Set up monitoring and alerting
- Test disaster recovery procedures
- Review security hardening checklist
