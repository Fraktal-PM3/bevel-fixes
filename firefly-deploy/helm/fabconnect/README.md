# FabConnect Helm Chart

This Helm chart deploys Hyperledger Firefly FabConnect, which connects to a Hyperledger Fabric blockchain peer.

## Prerequisites

Before installing this chart, you need to create a Kubernetes secret containing the MSP directory:

### MSP Secret

Contains the complete Membership Service Provider directory structure:

```bash
kubectl create secret generic fabconnect-msp \
  --from-file=/path/to/your/organizations/directory
```

The MSP directory should contain the complete Fabric organizations structure that will be mounted at `/etc/firefly/organizations`. This typically includes:
- `peerOrganizations/<org>/msp/`
- `peerOrganizations/<org>/peers/`
- `peerOrganizations/<org>/users/`
- `ordererOrganizations/`

## Quick Start Configuration

The chart uses a parameterized approach for easy configuration. The key values you'll want to override are at the top of `values.yaml`:

```yaml
peerUrl: grpcs://peer0.org1.example.com:7051
ordererUrl: grpcs://orderer.example.com:7050
caUrl: https://ca_org1:7054
organizationName: org1.example.com
organizationMspId: Org1MSP
channelName: pm3
enrollId: admin
enrollSecret: adminpw
```

These values are automatically templated into the Connection Profile (CCP), making it easy to customize via Ansible or other automation tools.

## Installation

Install the chart with the release name `fabconnect`:

```bash
helm install fabconnect . -n <namespace>
```

Or with custom values:

```bash
helm install fabconnect . -n <namespace> -f custom-values.yaml
```

## Configuration

### Key Parameters (Top-level for easy automation)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `peerUrl` | Fabric peer URL | `grpcs://peer0.org1.example.com:7051` |
| `ordererUrl` | Fabric orderer URL | `grpcs://orderer.example.com:7050` |
| `caUrl` | Certificate Authority URL | `https://ca_org1:7054` |
| `organizationName` | Organization domain name | `org1.example.com` |
| `organizationMspId` | Organization MSP ID | `Org1MSP` |
| `channelName` | Fabric channel name | `pm3` |
| `enrollId` | CA enrollment ID | `admin` |
| `enrollSecret` | CA enrollment secret | `adminpw` |

### Other Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | FabConnect image repository | `ghcr.io/hyperledger/firefly-fabconnect` |
| `image.tag` | Image tag (SHA256) | `sha256:a52dd8c60802562a3752015480af590b7f350fc165297c62a077394d7c49557c` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `replicaCount` | Number of replicas | `1` |
| `config.maxInFlight` | Max in-flight transactions | `10` |
| `config.maxTXWaitTime` | Max transaction wait time | `60` |
| `config.sendConcurrency` | Send concurrency | `25` |
| `config.port` | HTTP server port | `3000` |
| `config.webhooksAllowPrivateIPs` | Allow webhooks to private IPs | `true` |
| `mspSecret` | Name of the MSP secret | `fabconnect-msp` |
| `service.type` | Kubernetes service type | `ClusterIP` |
| `service.port` | Service port | `3000` |
| `healthcheck.enabled` | Enable health checks | `true` |
| `healthcheck.path` | Health check path | `/status` |

## Volume Mounts

The chart mounts the following:

- `/fabconnect/fabconnect.yaml` - FabConnect configuration (from ConfigMap)
- `/fabconnect/ccp.yaml` - Connection profile (auto-generated from ConfigMap using values)
- `/etc/firefly/organizations` - MSP directory (from `mspSecret`)
- `/fabconnect/receipts` - Receipt storage (emptyDir)
- `/fabconnect/events` - Event storage (emptyDir)

## Automation with Ansible

The chart is designed to work seamlessly with Ansible. Here's an example playbook:

```yaml
---
- name: Deploy FabConnect
  hosts: localhost
  vars:
    namespace: firefly
    peer_url: "grpcs://peer0.org2.example.com:7051"
    orderer_url: "grpcs://orderer.example.com:7050"
    org_name: "org2.example.com"
    org_msp_id: "Org2MSP"
    channel: "mychannel"

  tasks:
    - name: Create namespace
      kubernetes.core.k8s:
        name: "{{ namespace }}"
        kind: Namespace
        state: present

    - name: Create MSP secret
      kubernetes.core.k8s:
        state: present
        definition:
          apiVersion: v1
          kind: Secret
          metadata:
            name: fabconnect-msp
            namespace: "{{ namespace }}"
          type: Opaque
          data:
            # Your base64-encoded MSP files here

    - name: Deploy FabConnect with Helm
      kubernetes.core.helm:
        name: fabconnect
        chart_ref: ./helm/fabconnect
        release_namespace: "{{ namespace }}"
        values:
          peerUrl: "{{ peer_url }}"
          ordererUrl: "{{ orderer_url }}"
          organizationName: "{{ org_name }}"
          organizationMspId: "{{ org_msp_id }}"
          channelName: "{{ channel }}"
          enrollId: admin
          enrollSecret: adminpw
```

## Health Checks

The deployment includes liveness and readiness probes that check the `/status` endpoint on port 3000.

## Example Values Override

### Using a custom values file

```yaml
# custom-values.yaml
peerUrl: grpcs://peer0.org2.example.com:7051
ordererUrl: grpcs://orderer2.example.com:7050
organizationName: org2.example.com
organizationMspId: Org2MSP
channelName: mychannel

replicaCount: 2

config:
  maxInFlight: 20
  sendConcurrency: 50

service:
  type: LoadBalancer

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 250m
    memory: 256Mi
```

### Using --set flags

```bash
helm install fabconnect . \
  --set peerUrl=grpcs://peer0.org2.example.com:7051 \
  --set ordererUrl=grpcs://orderer2.example.com:7050 \
  --set organizationName=org2.example.com \
  --set organizationMspId=Org2MSP \
  --set channelName=mychannel
```

## Accessing FabConnect

Once deployed, you can access FabConnect within the cluster at:

```
http://fabconnect-<release-name>.<namespace>.svc.cluster.local:3000
```

For external access, use port-forwarding:

```bash
kubectl port-forward -n <namespace> svc/fabconnect-<release-name> 3000:3000
```

Then access at `http://localhost:3000`

## Uninstall

```bash
helm uninstall fabconnect -n <namespace>
```

Note: This will not delete the secrets. Delete them manually if needed:

```bash
kubectl delete secret fabconnect-ccp fabconnect-msp -n <namespace>
```
