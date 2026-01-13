## External DNS Role

This Ansible role deploys External DNS to a Kubernetes cluster to automate DNS record management for Ingress resources.

### Purpose

External DNS automatically creates and manages DNS records in cloud DNS providers (Cloudflare, AWS Route53, Google Cloud DNS) based on Kubernetes Ingress resources. This eliminates the need for manual DNS configuration.

### Supported Providers

- **Cloudflare**: Using API tokens
- **AWS Route53**: Using IAM credentials
- **Google Cloud DNS**: Using service account JSON

### Prerequisites

Before running this role, you must create a Kubernetes secret containing your DNS provider credentials:

#### Cloudflare
```bash
kubectl create secret generic cloudflare-api-token \
  --from-literal=cloudflare_api_token=<YOUR_API_TOKEN> \
  -n kube-system
```

#### AWS Route53
```bash
kubectl create secret generic aws-credentials \
  --from-literal=aws_access_key_id=<YOUR_ACCESS_KEY> \
  --from-literal=aws_secret_access_key=<YOUR_SECRET_KEY> \
  -n kube-system
```

#### Google Cloud DNS
```bash
kubectl create secret generic gcp-credentials \
  --from-file=credentials.json=<PATH_TO_SERVICE_ACCOUNT_JSON> \
  -n kube-system
```

### Configuration in network.yaml

Enable External DNS and configure the provider in your `network.yaml`:

```yaml
network:
  env:
    external_dns: enabled
    external_dns_provider: cloudflare  # or 'aws' or 'google'
    external_dns_version: "0.14.0"     # Optional
    external_dns_policy: sync          # Optional: 'sync' or 'upsert-only'
    external_dns_owner_id: bevel-fabric-network  # Optional
    external_dns_log_level: info       # Optional: 'debug', 'info', 'warning', 'error'
    external_dns_interval: 1m          # Optional: sync interval
    
    # Cloudflare-specific (optional)
    cloudflare_proxied: "false"  # Must be false for GRPC
    
    # AWS-specific (optional)
    aws_region: us-east-1
    aws_zone_type: public
    aws_hosted_zone_id: "MyZone"
    
    # GCP-specific (optional)
    gcp_project: my-project-id
    
  organizations:
    - organization:
        name: pm3org
        external_url_suffix: pm3org-net.pm3fraktal.se
```

### How It Works

1. **Deployment**: The role checks if External DNS is already installed
2. **Validation**: Verifies DNS provider configuration and credentials
3. **Template Generation**: Creates provider-specific deployment manifest
4. **Installation**: Deploys External DNS to `kube-system` namespace
5. **Verification**: Waits for pod to be ready and displays logs

### Integration with Bevel

This role is automatically called by `setup-k8s-environment.yaml` when:
- `network.env.external_dns` is set to `enabled`
- A valid `external_dns_provider` is specified

The role will:
- Deploy External DNS once per cluster
- Skip deployment if already installed
- Fail fast if credentials are missing
- Display status and logs for troubleshooting

### DNS Record Creation

After External DNS is deployed, it will automatically:
1. Watch for Ingress resources created by Bevel
2. Detect annotations added by HAProxy/Istio/Edge-Stack roles
3. Create DNS A records pointing to the LoadBalancer IP
4. Create TXT records for ownership tracking
5. Update records when Ingress resources change
6. Delete records when Ingress resources are removed

### Troubleshooting

#### Check External DNS Status
```bash
kubectl get pods -n kube-system -l app=external-dns
kubectl logs -n kube-system -l app=external-dns -f
```

#### Common Issues

1. **No DNS records created**: Check if LoadBalancer has external IP
   ```bash
   kubectl get svc -n ingress-controller haproxy-ingress
   ```

2. **Permission errors**: Verify API credentials are correct
   ```bash
   kubectl get secret -n kube-system cloudflare-api-token
   ```

3. **Domain filter mismatch**: Ensure `external_url_suffix` matches domain filter
   ```bash
   kubectl logs -n kube-system -l app=external-dns | grep "domain-filter"
   ```

### Variables

The role uses the following variables from `network.yaml`:

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `external_dns` | Yes | - | Set to 'enabled' to deploy |
| `external_dns_provider` | Yes | cloudflare | DNS provider: cloudflare, aws, google |
| `external_dns_version` | No | 0.14.0 | External DNS version |
| `external_dns_policy` | No | sync | Policy: sync or upsert-only |
| `external_dns_owner_id` | No | bevel-fabric-network | Unique identifier for TXT records |
| `external_dns_log_level` | No | info | Log level: debug, info, warning, error |
| `external_dns_interval` | No | 1m | Sync interval |
| `cloudflare_proxied` | No | false | Enable Cloudflare proxy (must be false for GRPC) |
| `aws_region` | No | - | AWS region for Route53 |
| `gcp_project` | No | - | GCP project ID |

### Files Generated

The role generates deployment manifests in `build/`:
- `build/external-dns-cloudflare.yaml`
- `build/external-dns-aws.yaml`
- `build/external-dns-google.yaml`

These files can be used for manual deployment or troubleshooting.
