# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a Hyperledger Bevel deployment repository customized for deploying Hyperledger Fabric networks on minikube with HAProxy ingress, external DNS (Cloudflare), and Hyperledger FireFly integration. It's based on the official [Hyperledger Bevel](https://github.com/hyperledger/bevel) framework but contains custom automation scripts and configuration for the PM3 network.

## Key Commands

### Network Deployment

```bash
# Deploy complete Fabric network (includes External DNS, HAProxy, and Fabric)
./run.sh

# Reset/cleanup the network
./reset.sh

# Deploy FireFly layer on top of existing Fabric network
./deploy-firefly.sh
```

### Prerequisites for Deployment

1. **Start minikube cluster:**
   ```bash
   minikube start --memory=8192 --cpus=4
   ```

2. **Start minikube tunnel** (in separate terminal, keep running):
   ```bash
   minikube tunnel
   ```

3. **Set KUBECONFIG:**
   ```bash
   export KUBECONFIG=/home/hedlund01/bevel-fixes/build/config
   ```

### Validation and Schema

```bash
# Validate network.yaml against schema
ajv validate -s /home/hedlund01/bevel-fixes/platforms/network-schema.json \
  -d /home/hedlund01/bevel-fixes/build/network.yaml
```

### Manual Operations

```bash
# Create channels manually
./create-channels.sh

# Install chaincode manually
./install-chaincode.sh

# Setup port forwarding for local access
./setup-port-forwarding.sh

# Setup External DNS (done automatically by run.sh)
./setup-external-dns.sh
```

### Kubernetes Operations

```bash
# Check pod status
kubectl get pods -A

# Watch all pods
kubectl get pods -A -w

# Check HAProxy LoadBalancer IP
kubectl get svc -n ingress-controller haproxy-ingress

# View External DNS logs
kubectl logs -n kube-system -l app=external-dns -f

# Force Flux reconciliation
kubectl annotate gitrepository flux-local -n flux-local \
  reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite
```

### FireFly Operations

```bash
# Delete FireFly pod and configmap to force restart
su - hedlund01 -c "minikube kubectl -- delete configmap firefly-fabconnect-ccp -n default && \
  minikube kubectl -- delete pod firefly-fabconnect-0 -n default"

# Check FireFly pod status
su - hedlund01 -c "minikube kubectl -- get pod firefly-fabconnect-0 -n default"

# Get FireFly resources
su - hedlund01 -c "minikube kubectl -- get all,jobs -n transporter1-net | grep firefly"

# Check enrollment jobs across all namespaces
su - hedlund01 -c "minikube kubectl -- get jobs -A | grep enroll"
```

## Architecture

### High-Level Structure

**Hyperledger Bevel** is a framework for deploying production-ready DLT networks using:
- **Helm charts** for deploying DLT components (orderers, peers, CAs)
- **Ansible playbooks** for orchestrating deployments
- **GitOps** integration via Flux for continuous deployment
- **Multiple DLT platforms:** Fabric, Corda, Besu, Quorum, Indy, Substrate

This repository focuses on **Hyperledger Fabric 2.5.4**.

### Directory Structure

```
platforms/
├── hyperledger-fabric/
│   ├── charts/               # Helm charts for Fabric components
│   │   ├── fabric-ca-server/
│   │   ├── fabric-orderernode/
│   │   ├── fabric-peernode/
│   │   ├── fabric-chaincode-install/
│   │   ├── fabric-chaincode-approve/
│   │   ├── fabric-chaincode-commit/
│   │   ├── fabric-channel-join/
│   │   └── fabric-genesis/
│   └── configuration/        # Ansible roles and playbooks
│       └── roles/
├── firefly/                  # FireFly deployment (custom)
│   └── configuration/
├── shared/                   # Common Ansible roles and playbooks
│   ├── configuration/
│   │   ├── site.yaml        # Main orchestration playbook
│   │   ├── setup-environment.yaml
│   │   └── setup-k8s-environment.yaml
│   ├── charts/              # Shared Helm charts
│   └── inventory/           # Ansible inventory (localhost-based)
└── network-schema.json      # JSON schema for network.yaml validation

build/
├── network.yaml             # Main configuration file (defines entire network)
├── config                   # Kubernetes config file (minikube)
└── *.md                     # Custom documentation for this deployment

firefly-helm-charts/         # FireFly Helm charts and deployment
└── charts/firefly/
```

### Deployment Flow

1. **run.sh** executes:
   - Validates `build/network.yaml` against schema
   - Runs `setup-external-dns.sh` to create Cloudflare credentials
   - Calls Ansible playbook: `platforms/shared/configuration/site.yaml`

2. **site.yaml** orchestrates:
   - `setup-environment.yaml` - Controller prerequisites
   - `setup-k8s-environment.yaml` - Flux, HAProxy, External DNS
   - `hyperledger-fabric/configuration/deploy-network.yaml` - Fabric network

3. **deploy-network.yaml** deploys (in order):
   - CA servers for each organization
   - Crypto material generation
   - Genesis block creation
   - Orderer nodes
   - Peer nodes
   - Channel creation and peers joining
   - Chaincode installation, approval, and commit

### Network Configuration Architecture

All network configuration is centralized in `build/network.yaml`:

- **Network type and version** (`network.type: fabric`, `network.version: 2.5.4`)
- **Environment settings** (`network.env`):
  - Proxy type (haproxy)
  - External DNS configuration (Cloudflare)
  - Kubernetes cluster type (local/minikube)
- **Organizations** (`network.organizations[]`):
  - CA, orderer, and peer specifications
  - Vault paths for crypto storage
  - Kubernetes namespaces
  - External URL suffixes
- **Channels** (`network.channels[]`):
  - Participating organizations and peers
  - Chaincodes to deploy
  - Endorsement policies
  - Channel creation/join participants

### Chaincode Deployment

Chaincode installation uses Helm jobs that:

1. Download chaincode from Git/package URL
2. Install Node.js/Go dependencies
3. **Special handling for pm3roleauth chaincode:** Replace hardcoded `Org1MSP` with `pm3orgMSP` in `src/roleAuthContract.ts` (see [fabric-chaincode-install/templates/install_chaincode.yaml:269-275](platforms/hyperledger-fabric/charts/fabric-chaincode-install/templates/install_chaincode.yaml#L269-L275))
4. Package chaincode
5. Install on peer
6. Approve and commit (separate Helm charts)

### Vault Integration

HashiCorp Vault is used for:
- Storing organization crypto material (MSPs, TLS certs)
- Secure credential management
- Path format: `secretsv2/local<orgname>/`

### External DNS and HAProxy

- **External DNS** automatically creates DNS records in Cloudflare for all Ingress resources
- **HAProxy** provides ingress with TLS termination
- Domain: `pm3fraktal.se`
- Organization-specific subdomains: `<component>.<orgname>-net.pm3fraktal.se`

Example URLs:
- `orderer1.pm3org-net.pm3fraktal.se:443`
- `peer0.transporter1-net.pm3fraktal.se:443`
- `ca.ombud1-net.pm3fraktal.se:443`

### FireFly Integration

FireFly provides a Web3 gateway for the Fabric network:
- Deployed via `deploy-firefly.sh`
- Uses Fabconnect to interact with Fabric
- Requires MSP certificates synced from Vault
- Each organization can run a FireFly node

## Important Configuration Notes

### network.yaml Structure

The `build/network.yaml` file is the single source of truth. Key sections:

1. **Consensus:** RAFT with 3 orderers (odd number for majority)
2. **Channels:** `pm3` channel with chaincodes: `firefly-go`, `pm3package`, `pm3roleauth`
3. **Organizations:**
   - `pm3org` - Orderer organization with peer
   - `transporter1` - Peer organization (channel creator)
   - `ombud1` - Peer organization
   - `ombud2` - Peer organization
4. **Endorsement Policy:** Requires endorsement from all 4 organizations

### Chaincode-Specific Configuration

**pm3roleauth chaincode** requires MSP ID replacement during installation because it contains hardcoded organization references. The installation job automatically patches this in the downloaded source before packaging.

### HAProxy Configuration

HAProxy is configured via `network.env.proxy: haproxy` and requires:
- LoadBalancer service with external IP
- TLS passthrough for GRPC (gRPC doesn't work with Cloudflare proxy)
- Annotations on services to trigger External DNS

### Common Ansible Roles

Key roles in `platforms/shared/configuration/roles/`:
- `setup/flux` - GitOps with Flux
- `setup/haproxy` - HAProxy ingress controller
- `setup/external-dns` - External DNS setup
- `setup/vault_kubernetes` - Vault auth configuration
- `create/namespace` - K8s namespace creation
- `create/secrets/docker_secret` - Registry credentials

## Development Workflow

### Making Changes to Network

1. Edit `build/network.yaml`
2. Validate: `ajv validate -s platforms/network-schema.json -d build/network.yaml`
3. Deploy changes: `./run.sh`
4. To reset: `./reset.sh` then `./run.sh`

### Adding a New Organization

Follow the pattern in `build/network.yaml`:
1. Add to `network.organizations[]`
2. Add to channel participants in `network.channels[].participants[]`
3. Add to endorsers if needed
4. Update orderer URIs if the new org has orderers
5. Run `./run.sh` or use `add-organization.yaml` playbook

### Deploying New Chaincode

1. Add chaincode definition to channel in `build/network.yaml`:
   ```yaml
   channels:
     - channel:
       chaincodes:
         - "chaincode-name"
   ```

2. Deploy using Ansible playbook or manual Helm charts:
   ```bash
   helm install <chaincode-name> \
     ./platforms/hyperledger-fabric/charts/fabric-chaincode-install \
     --namespace <org>-net \
     --values <values-file>.yaml
   ```

### Debugging Deployment Issues

1. **Check Ansible logs:** Look for failed tasks in run.sh output
2. **Check Helm releases:**
   ```bash
   helm list -A
   ```
3. **Check pod logs:**
   ```bash
   kubectl logs -n <namespace> <pod-name>
   ```
4. **Check Helm job logs:**
   ```bash
   kubectl logs -n <namespace> job/<job-name>
   ```
5. **Describe resources for events:**
   ```bash
   kubectl describe pod -n <namespace> <pod-name>
   ```

### Testing Fabric Network

```bash
# Execute commands in peer CLI
kubectl exec -it -n transporter1-net peer0-0 -- bash

# Inside pod:
peer channel list
peer lifecycle chaincode queryinstalled
peer chaincode query -C pm3 -n <chaincode> -c '{"Args":["function","arg1"]}'
```

## Documentation Files

### Primary Documentation

- [README.md](README.md) - Official Bevel README
- [CONTRIBUTING.md](CONTRIBUTING.md) - Contribution guidelines
- [build/QUICKSTART.md](build/QUICKSTART.md) - Quick start for this deployment
- [build/AUTOMATED_DEPLOYMENT_GUIDE.md](build/AUTOMATED_DEPLOYMENT_GUIDE.md) - Detailed External DNS deployment guide
- [build/HAPROXY_NETWORK_GUIDE.md](build/HAPROXY_NETWORK_GUIDE.md) - HAProxy ingress setup

### Fabric Charts Documentation

- [platforms/hyperledger-fabric/charts/README.md](platforms/hyperledger-fabric/charts/README.md) - Comprehensive Helm charts guide

### Platform-Specific READMEs

Each platform directory has its own README:
- `platforms/hyperledger-fabric/configuration/README.md`
- `platforms/shared/configuration/README.md`

### Custom Documentation

- [EXPORT_CERTS.md](EXPORT_CERTS.md) - Exporting MSP certs from Vault for external use
- [FLUXRECONCILE.md](FLUXRECONCILE.md) - Force Flux to reconcile

### FireFly Documentation

Located in `firefly-helm-charts/`:
- `QUICKSTART.md` - FireFly deployment quick start
- `FIREFLY-FABCONNECT-DEPLOYMENT-GUIDE.md` - Detailed FireFly setup
- `VAULT-MSP-SYNC.md` - Syncing MSP from Vault to FireFly

## Testing

### Validation Before Deployment

```bash
# Schema validation
ajv validate -s platforms/network-schema.json -d build/network.yaml

# YAML linting (if configured)
yamllint build/network.yaml
```

### Post-Deployment Tests

```bash
# Check all pods are running
kubectl get pods -A | grep -v Running

# Check Fabric network info
kubectl exec -n transporter1-net peer0-0 -- peer channel list

# Query chaincode
kubectl exec -n transporter1-net peer0-0 -- \
  peer chaincode query -C pm3 -n firefly-go -c '{"Args":["ping"]}'

# Test DNS resolution
dig peer0.transporter1-net.pm3fraktal.se +short

# Test TLS connection
openssl s_client -connect peer0.transporter1-net.pm3fraktal.se:443
```

## Troubleshooting Common Issues

### External DNS Not Creating Records

1. Check External DNS pod logs: `kubectl logs -n kube-system -l app=external-dns -f`
2. Verify Cloudflare credentials: `kubectl get secret cloudflare-api-token -n kube-system`
3. Check HAProxy has external IP: `kubectl get svc -n ingress-controller haproxy-ingress`
4. Ensure `minikube tunnel` is running

### Pods Stuck in Pending

1. Check pod events: `kubectl describe pod -n <namespace> <pod-name>`
2. Check PVC status: `kubectl get pvc -A`
3. Verify resource limits: `kubectl describe node`

### Chaincode Installation Fails

1. Check chaincode install job logs: `kubectl logs -n <namespace> job/<chaincode>-install`
2. Verify chaincode source URL is accessible
3. Check for missing dependencies in chaincode
4. For pm3roleauth: verify the sed replacement is working

### Vault Connection Issues

1. Verify Vault is accessible: `kubectl get pods -n <vault-namespace>`
2. Check Vault secrets: `kubectl get secrets -n <org-namespace> | grep vault`
3. Verify Vault token is valid

### FireFly Not Starting

1. Check MSP sync from Vault completed
2. Verify Fabconnect connection profile is correct
3. Check FireFly pod logs: `kubectl logs -n <namespace> <firefly-pod>`
4. Ensure Fabric network is fully operational first

## Git Workflow

### Commit Convention

Follow Conventional Commits with platform prefix:
- `[fabric]` for Hyperledger Fabric changes
- `[shared]` for common changes
- `[corda]`, `[besu]`, `[indy]`, `[quorum]` for other platforms

Example:
```
[fabric] feat: add support for external chaincode deployment

Updated fabric-external-chaincode chart to support...

Fixes #123
```

### Branching

- `main` - Stable production branch
- `develop` - Development branch (default for PRs)
- Feature branches: `feat-<issue-number>`

### Before Committing

1. Sign commits: `git commit -s`
2. Squash to single commit
3. Test deployment in minikube
4. Update relevant documentation

## Additional Resources

- Hyperledger Bevel Docs: https://hyperledger-bevel.readthedocs.io/
- Hyperledger Fabric Docs: https://hyperledger-fabric.readthedocs.io/
- Hyperledger FireFly: https://hyperledger.github.io/firefly/
- HAProxy Ingress: https://haproxy-ingress.github.io/
- External DNS: https://github.com/kubernetes-sigs/external-dns
