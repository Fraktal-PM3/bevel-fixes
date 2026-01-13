# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository contains official Helm charts for deploying Hyperledger FireFly (multi-party blockchain middleware) and its microservice connectors on Kubernetes. The main chart is `firefly`, which orchestrates deployment of FireFly core along with optional components for blockchain connectivity, token management, data exchange, and shared storage.

## Common Development Commands

### Quick Start
```bash
make stack
```
Creates a complete local environment in kind with PostgreSQL, Hyperledger Fabric with FabConnect connector, and FireFly.

### Development Workflow
```bash
make kind          # Create local Kubernetes cluster via kind
make deps          # Install dependencies (cert-manager, PostgreSQL, IPFS, Prometheus)
make starter       # Copy eth-values.yaml to local-values.yaml as template
# Edit charts/firefly/local-values.yaml with your configuration
make deploy        # Deploy FireFly with custom values
```

### Testing
```bash
make lint          # Run helm template validation, ct lint, and license header checks
make test          # Run chart-testing integration tests
make e2e           # Full end-to-end: kind + deps + test
```

### Multiparty Mode
After deploying the stack, enable advanced messaging features:
```bash
./hack/multiparty.sh
```
This script deploys the multiparty contract, updates configuration, and registers org/node. When upgrading after multiparty is enabled, include the multiparty values:
```bash
helm upgrade --install firefly ./charts/firefly \
  -f ./charts/firefly/local-kind-values.yaml \
  -f ./hack/multiparty-values.yaml
```

### Chart Updates
After modifying chart dependencies in Chart.yaml:
```bash
helm dep up charts/firefly
```

## Chart Architecture

### Five Independent Charts

1. **firefly** (v0.9.1, app v1.3.3) - Main chart containing:
   - FireFly core (StatefulSet)
   - DataExchange HTTPS (StatefulSet for peer-to-peer communication)
   - Optional: ethconnect, erc20erc721, erc1155, sandbox
   - Declares dependencies on firefly-evmconnect and firefly-fabconnect charts

2. **firefly-evmconnect** (v0.8.1) - Modern EVM blockchain connector with LevelDB persistence

3. **firefly-fabconnect** (v0.1.0) - Hyperledger Fabric blockchain connector with LevelDB persistence for receipts and events

4. **firefly-signer** (v0.8.0) - Transaction signing service

5. **ipfs** (v0.7.0) - Private IPFS node for shared storage

### Template Organization Pattern

Each component follows consistent structure:
- `<component>/statefulset.yaml` or `deployment.yaml`
- `<component>/service.yaml`
- `<component>/ingress.yaml` (optional)
- `<component>/secret.yaml` or `configmap.yaml`
- `<component>/job-*.yaml` (initialization jobs)

### Critical Helper Functions (_helpers.tpl)

**`firefly.coreConfig`** (lines 216-482): The most important template function. Generates the entire FireFly configuration YAML by:
- Conditionally rendering plugin sections based on enabled features
- Auto-discovering service URLs within K8s cluster
- Supporting both Ethereum (ethconnect/evmconnect) and Fabric (fabconnect) blockchains
- Building namespace configuration with multiparty settings

**`firefly.nodeName`**: Creates globally unique node names using namespace + release name for peer discovery

**Component label helpers**: Seven pairs of `*Labels` and `*SelectorLabels` functions for consistent labeling

**`firefly.coreHttpPublicURL`**: Computes public URL using Ingress host or falls back to ClusterIP service

## Configuration Patterns

### Key Values Files

- **local-kind-values.yaml**: Local development on kind cluster with in-cluster services
- **eth-values.yaml**: Ethereum configuration for CI with external ethconnect
- **fab-values.yaml**: Fabric configuration using fabconnect and chaincode
- **mtls-values.yaml**: Mutual TLS configuration demonstrating certificate mounting
- **multiparty-values.yaml**: Dynamically updated by multiparty.sh script with contract addresses

### Plugin Override System

Each auto-configured plugin section has two escape hatches:
- `<plugin>Override`: Completely replace default templating
- `extra<Plugin>s`: Add additional plugin instances

Examples: `config.blockchainOverride`, `config.extraBlockchains`, `config.databaseOverride`

For complete configuration replacement, use `config.templateOverride`.

### Multiparty Configuration

Controlled by `config.multipartyEnabled` boolean. When true, the coreConfig helper generates:
```yaml
multiparty:
  enabled: true
  org:
    name: <organizationName>
    key: <organizationKey or fabconnectSigner>
  node:
    name: <unique node name>
  contract:
    - location: {address/chaincode config}
      firstEvent: <block number>
```

Contract details are populated from `fireflyContracts` array, which is updated by the multiparty.sh script.

### URL Auto-Discovery

The chart auto-computes service URLs using pattern: `<release-name>-<component>.<namespace>.svc:<port>`

This allows charts to reference each other without hardcoding URLs. Override by providing explicit URL values (e.g., `config.ethconnectUrl`, `config.postgresUrl`).

## Key Architectural Concepts

### StatefulSet vs Deployment Usage

**StatefulSets are used for**:
- **firefly core**: Stable network identity needed for peer-to-peer discovery
- **dataexchange**: Persistent storage for peer certificates and blobs (2 PVCs: dx-peers, dx-blobs)
- **evmconnect/ethconnect**: LevelDB persistence for transaction nonce management and event checkpoints (critical for preventing duplicate transactions)

**Deployments are used for**:
- **erc20erc721, erc1155**: Stateless token connectors
- **sandbox**: Stateless UI
- **ipfs**: Data is persistent but no stable identity needed

Key difference: StatefulSets provide stable DNS names (pod-0, pod-1) essential for services that peers must reliably discover.

### Job-Based Initialization

Three job types handle initialization:

1. **Database Migration** (core/job-migrations.yaml): Creates database and runs migrations
   - Job name includes image tag to ensure new job on every image update
   - Only runs if `core.jobs.postgresMigrations.enabled=true`

2. **Contract Registration** (ethconnect/job-register-contracts.yaml): Registers FireFly contract ABIs
   - Polls ethconnect health endpoint until ready
   - Uses ConfigMap for contract JSON files

3. **Contract Deployment** (erc20erc721/job-deploy-contracts.yaml): Deploys token contracts
   - Runs npm install + node.js deployment scripts
   - Controlled by environment variables for ERC20/ERC721 selection

All jobs use `backoffLimit: 5` and `activeDeadlineSeconds: 12000` (3.3 hours) for resilience.

### Conditional Component Deployment

Multi-level conditional structure:
1. Top-level component enable: `{{- if .Values.dataexchange.enabled }}`
2. Sub-feature conditionals: `{{- if and .Values.dataexchange.enabled .Values.dataexchange.certificate.enabled }}`
3. Configuration conditionals in helpers: `{{- if or .Values.config.ethconnectUrl .Values.ethconnect.enabled }}`

Complex example from _helpers.tpl (lines 424-435):
```go
{{- if and (eq .Values.config.defaultBlockchainType "ethereum") (or .Values.config.evmconnectUrl .Values.evmconnect.enabled .Values.config.ethconnectUrl .Values.ethconnect.enabled) }}
  defaultKey: {{ .Values.config.organizationKey }}
{{- else if .Values.config.fabconnectUrl }}
  defaultKey: {{ .Values.config.fabconnectSigner }}
{{- end }}
```

This determines blockchain plugin and signing key format.

### Multi-Blockchain Support

FireFly uses a plugin architecture abstracting blockchain type:

**Ethereum-based** (eth0 plugin):
- Legacy: ethconnect (deprecated but supported)
- Modern: evmconnect (recommended)
- Helper function `firefly.ethconnectUrlEnvVar` (lines 484-495) abstracts the difference

**Fabric-based** (fabric0 plugin):
- fabconnect connector
- Different config keys: channel, chaincode, signer (vs. address for Ethereum)
- Contract location uses `{chaincode, channel}` instead of `{address}`

Selection mechanism:
- `config.defaultBlockchainType` (ethereum/fabric) determines default namespace binding
- Multiple blockchain plugins can coexist in same deployment via `config.extraBlockchains`

### Advanced Patterns

**Config Checksum Annotation**: StatefulSets include config Secret checksum in pod annotations:
```yaml
checksum/config: {{ include (print $.Template.BasePath "/core/secret.yaml") . | sha256sum }}
```
Forces pod restart when configuration changes.

**Probe Configuration for PreInit Mode**: Readiness probes check admin port instead of http when `config.preInit=true` since the main API isn't ready until manual configuration is completed.

**cert-manager Integration**: Certificate resources check for cert-manager capability and warn if not available. Supports both generated certs and pre-existing tlsSecret.

## Testing and CI/CD

### Local Testing
1. `make kind` - Create disposable cluster
2. `make deps` - Install full dependency stack
3. `make test` - Run ct install integration tests
4. OR `make deploy` - Manual testing with custom values
5. Debug with `kubectl logs` / `kubectl get pods`
6. `make clean` - Delete kind cluster

### Linting Process (make lint)
Three-stage validation:
1. `helm dep up charts/firefly` - Update dependencies
2. `helm template` - Validate template rendering with multiple connectors enabled
3. `ct lint` - YAML formatting validation using lintconf.yaml
4. `./hack/enforce-chart-conventions.sh` - Ensure all templates have Apache license headers

### CI/CD Workflow (.github/workflows/helm.yml)

**Test Job**:
- Sets up Helm 3.7.2 and chart-testing v2.2.0
- Runs `make lint`
- Creates kind cluster v0.20.0
- Installs dependencies
- Integration test currently disabled (line 47-48)

**Release Job** (on push to main or release):
- Extracts chart version from Chart.yaml
- Builds version string:
  - Push events: `<version>-YYYYMMDD-<run-number>` (daily snapshots)
  - Release events: Validates git tag matches chart version
- Publishes to GHCR OCI registry with `HELM_EXPERIMENTAL_OCI=1`
- Publishes both firefly-evmconnect standalone and firefly with dependencies

### Chart Convention Enforcement
Custom script `hack/enforce-chart-conventions.sh` ensures all YAML templates include Apache 2.0 license header. This runs as part of the lint process.

## Important Notes

- All configuration values are documented in charts/firefly/values.yaml (664 lines)
- Chart supports Kubernetes 1.18+ and requires Helm 3.7+
- For production deployments, review security contexts, RBAC, and TLS configuration in values files
- The chart is designed for both single-node development and multi-party production networks
- When testing blockchain integration, ensure your blockchain node is accessible from the cluster
