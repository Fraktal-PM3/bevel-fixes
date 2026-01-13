# FireFly Deployment for Hyperledger Bevel

This directory contains Ansible playbooks and roles for deploying Hyperledger FireFly on top of an existing Hyperledger Fabric network managed by Bevel.

## Overview

FireFly is a multi-party system that enables secure data sharing and tokenization across organizations. This deployment:

- Deploys FireFly in existing Fabric organization namespaces
- Creates unique ingress URLs for each organization
- Configures FabConnect to connect to Fabric peers and orderers
- Sets up External DNS for automatic DNS record creation
- Enables multiparty mode for cross-organization communication

## Architecture

```
Organization Namespace: {org-name}-net
├── Fabric Components (already deployed)
│   ├── Peer
│   ├── CA
│   └── CLI
└── FireFly Components (deployed by this playbook)
    ├── FireFly Core
    ├── FabConnect (Fabric connector)
    ├── PostgreSQL (database)
    ├── IPFS (data sharing)
    ├── DataExchange (P2P communication)
    └── Sandbox UI
```

## Prerequisites

1. **Fabric Network**: A Fabric network must be deployed using Bevel
   - Organization namespaces must exist (`{org}-net`)
   - Peers must be running
   - Channel must be created
   - FireFly chaincode must be deployed

2. **Vault**: MSP credentials must be stored in Vault
   - Path: `secretsv2/local{orgname}/users/admin-msp`
   - Contains: admincerts, cacerts, keystore, signcerts, tlscacerts

3. **GitOps**: Flux must be configured
   - Git repository for values files
   - Flux syncing Helm releases

4. **External DNS**: For automatic DNS record creation
   - Configured with your DNS provider
   - Running in the Kubernetes cluster

5. **FireFly Helm Charts**: Must exist in the repository
   - Location: `firefly-helm-charts/charts/firefly/`

## Configuration

### Step 1: Update network.yaml

Add `firefly_config` section to each organization that should have FireFly:

```yaml
organizations:
  - organization:
      name: transporter1
      external_url_suffix: pm3fraktal.se
      # ... existing config ...

      firefly_config:
        enabled: true
        fabconnect_chaincode: "firefly-go"
        fabconnect_signer: "admin"
        fabconnect_retry: true
        multiparty_enabled: true
        dataexchange_enabled: true
        postgres_automigrate: true
        sandbox_enabled: true
        ipfs_enabled: true
        external_dns_target: "46.62.234.169"
```

See [firefly-config-example.yaml](./firefly-config-example.yaml) for complete example.

### Step 2: Validate Configuration

```bash
ajv validate -s platforms/network-schema.json -d build/network.yaml
```

## Deployment

### Deploy FireFly

```bash
bash deploy-firefly.sh
```

This script:
1. Validates network.yaml
2. Sets up environment variables
3. Runs the Ansible playbook
4. Syncs MSP credentials from Vault
5. Generates Helm values for each organization
6. Pushes values to GitOps repository
7. Waits for deployments

### Monitor Deployment

```bash
# Watch pods in organization namespace
kubectl get pods -n transporter1-net -w

# Check FireFly logs
kubectl logs -f firefly-0 -n transporter1-net

# Check FabConnect logs
kubectl logs -f firefly-fabconnect-0 -n transporter1-net
```

## Access FireFly

Each organization gets unique URLs for FireFly and Sandbox:

### transporter1
- **FireFly Core**: `http://firefly.transporter1-net.pm3fraktal.se`
- **Sandbox UI**: `http://sandbox.firefly.transporter1-net.pm3fraktal.se`

### ombud1
- **FireFly Core**: `http://firefly.ombud1-net.pm3fraktal.se`
- **Sandbox UI**: `http://sandbox.firefly.ombud1-net.pm3fraktal.se`

### ombud2
- **FireFly Core**: `http://firefly.ombud2-net.pm3fraktal.se`
- **Sandbox UI**: `http://sandbox.firefly.ombud2-net.pm3fraktal.se`

### Endpoints

- **FireFly API**: `http://firefly.{org}-net.{suffix}/api`
- **Swagger UI**: `http://firefly.{org}-net.{suffix}/api`
- **Sandbox UI**: `http://sandbox.firefly.{org}-net.{suffix}`
- **Health Check**: `http://firefly.{org}-net.{suffix}/api/v1/status`

## Troubleshooting

### Check MSP Secret

```bash
kubectl get secret fabconnect-msp -n transporter1-net
kubectl describe secret fabconnect-msp -n transporter1-net
```

### Verify Ingress

```bash
kubectl get ingress -n transporter1-net
kubectl describe ingress firefly -n transporter1-net
```

### Check DNS Records

```bash
nslookup firefly.transporter1-net.pm3fraktal.se
```

### Common Issues

1. **"Signer admin does not exist"**
   - Check that fabconnect-msp secret exists and has correct structure
   - Verify MSP files in Vault are accessible
   - Check FabConnect init container logs

2. **DNS not resolving**
   - Verify External DNS is running: `kubectl get pods -n kube-system | grep external-dns`
   - Check External DNS logs: `kubectl logs -n kube-system -l app=external-dns`
   - Verify ingress annotations are correct

3. **Cannot connect to Fabric**
   - Verify peer URLs are accessible
   - Check TLS certificates
   - Verify channel and chaincode names match

## Cleanup / Reset

### Remove All FireFly Deployments

To remove all FireFly deployments while preserving the Fabric network:

```bash
ansible-playbook -vv platforms/firefly/configuration/cleanup-firefly.yaml \
  --inventory-file=platforms/shared/inventory/ \
  -e "@build/network.yaml" \
  -e 'ansible_python_interpreter=/usr/bin/python3'
```

This will:
1. Remove FireFly Helm values from GitOps repository
2. Delete all Kubernetes resources (StatefulSets, Deployments, Services, Ingresses, ConfigMaps, PVCs)
3. Delete fabconnect-msp secrets
4. Remove DNS records (via External DNS)

### Full Network Reset

To reset both FireFly and the entire Fabric network:

```bash
bash reset.sh
```

This runs the cleanup playbook for FireFly first, then resets the Fabric network.

**Warning**: This will destroy all data. Use with caution.

## Directory Structure

```
platforms/firefly/configuration/
├── deploy-firefly.yaml                    # Main Ansible playbook
├── cleanup-firefly.yaml                   # Cleanup/reset playbook
├── firefly-config-example.yaml            # Configuration example
├── README.md                              # This file
└── roles/
    ├── create/
    │   ├── secrets/                       # MSP sync role
    │   │   └── tasks/
    │   │       └── main.yaml
    │   └── firefly_deployment/            # FireFly deployment role
    │       ├── tasks/
    │       │   └── main.yaml
    │       └── templates/
    │           └── firefly-values.yaml.j2  # Helm values template
    └── delete/
        ├── firefly_deployment/            # Remove values from GitOps
        │   └── tasks/
        │       └── main.yaml
        ├── k8s_resources/                 # Delete K8s resources
        │   └── tasks/
        │       └── main.yaml
        └── secrets/                       # Delete secrets
            └── tasks/
                └── main.yaml
```

## Files

- **deploy-firefly.yaml**: Main Ansible playbook that orchestrates deployment
- **roles/create/secrets**: Syncs MSP credentials from Vault to Kubernetes
- **roles/create/firefly_deployment**: Creates Helm values and deploys FireFly
- **firefly-values.yaml.j2**: Jinja2 template for Helm values file

## Support

For issues or questions:
1. Check the logs of FireFly and FabConnect pods
2. Verify all prerequisites are met
3. Review the firefly-config-example.yaml for correct configuration
4. Check Bevel documentation at https://hyperledger-bevel.readthedocs.io/
