# Guide: Exporting Fabric Organization MSP Certificates for External Fabconnect/Firefly Integration

This guide explains how to export the MSP (Membership Service Provider) certificates from HashiCorp Vault to an external device for use with Fabconnect and Hyperledger Firefly.

## Prerequisites

- Access to the Kubernetes cluster where Vault is running
- Vault CLI installed on your external device
- Network connectivity to the cluster

## Part 1: Setting Up External Vault Access

### Option A: Port Forwarding via SSH (Recommended for Remote Access)

If Vault is running in Docker on a remote host and you need to access it from your local machine:

```bash
# SSH tunnel from your local machine to the Vault host
ssh -L 8200:<vault-host-ip>:8200 <username>@<cluster-host>

# Example: ssh -L 8200:localhost:8200 user@vault-server.example.com
```

Access Vault at: `http://localhost:8200`

### Option B: Direct Access

If Vault is accessible directly from your network (same network or exposed):

```bash
export VAULT_ADDR="http://<vault-host-ip>:8200"
```

Access Vault at: `http://<vault-host-ip>:8200`

### Option C: VPN Access

If you're connecting through a VPN to the Docker host network:

```bash
export VAULT_ADDR="http://<vault-host-ip>:8200"
```

## Part 2: Installing Vault CLI on External Device

### Linux/Mac:
```bash
# Download and install Vault
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install vault

# Or using binary
wget https://releases.hashicorp.com/vault/1.15.2/vault_1.15.2_linux_amd64.zip
unzip vault_1.15.2_linux_amd64.zip
sudo mv vault /usr/local/bin/
```

### Windows:
Download from: https://www.vaultproject.io/downloads and add to PATH.

## Part 3: Authenticating with Vault

You'll need the Vault token. Get it from the cluster:

```bash
# On the cluster machine
cat ~/.vault-token
# Or
echo $VAULT_TOKEN
```

On your external device:

```bash
export VAULT_ADDR="http://localhost:8200"  # if using SSH tunnel
# OR
export VAULT_ADDR="http://<vault-host-ip>:8200"  # if direct access

export VAULT_TOKEN="<your-vault-token>"

# Verify connection
vault status
```

## Part 4: Exporting MSP Certificates

### Understanding the Directory Structure

Fabconnect requires the MSP directory structure to follow Hyperledger Fabric's standard format:

```
<orgname>/
├── msp/
│   ├── admincerts/
│   │   └── cert.pem
│   ├── cacerts/
│   │   └── ca.pem
│   ├── keystore/
│   │   └── key.pem
│   ├── signcerts/
│   │   └── cert.pem
│   └── tlscacerts/
│       └── tlsca.pem
└── tls/
    ├── ca.crt
    ├── client.crt
    └── client.key
```

### Script to Export Admin MSP and TLS Certificates

Create this script on your external device:

```bash
#!/bin/bash
# File: export-org-msp.sh

# Prompt for organization name
read -p "Enter organization name (e.g., ombud2, carrier, manufacturer): " ORG_NAME

# Validate input
if [ -z "$ORG_NAME" ]; then
    echo "Error: Organization name cannot be empty"
    exit 1
fi

# Prompt for vault path with a suggested default
read -p "Enter vault path [secretsv2/local${ORG_NAME}]: " VAULT_PATH
VAULT_PATH="${VAULT_PATH:-secretsv2/local${ORG_NAME}}"

ORG_DIR="./${ORG_NAME}"
MSP_DIR="${ORG_DIR}/msp"
TLS_DIR="${ORG_DIR}/tls"

# Set Vault address (update as needed)
export VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}" # Adjust if not using SSH tunnel

# Prompt for Vault root token
read -sp "Enter Vault root token: " VAULT_TOKEN
echo ""
export VAULT_TOKEN

echo "Exporting MSP and TLS certificates for ${ORG_NAME}..."
echo ""

# Create directory structure
echo "Creating directory structure..."
mkdir -p "${MSP_DIR}"/{signcerts,keystore,cacerts,tlscacerts,admincerts}
mkdir -p "${TLS_DIR}"

# Export MSP certificates
echo ""
echo "Exporting MSP certificates..."

# Export Admin Certificate (signcerts)
echo "  - Fetching admin certificate..."
vault kv get -field=admincerts "${VAULT_PATH}/users/admin-msp" >"${MSP_DIR}/signcerts/cert.pem"

# Export Private Key (keystore)
echo "  - Fetching private key..."
vault kv get -field=keystore "${VAULT_PATH}/users/admin-msp" >"${MSP_DIR}/keystore/key.pem"

# Export CA Certificate (cacerts)
echo "  - Fetching CA certificate..."
vault kv get -field=cacerts "${VAULT_PATH}/users/admin-msp" >"${MSP_DIR}/cacerts/ca.pem"

# Export TLS CA Certificate (tlscacerts)
echo "  - Fetching TLS CA certificate..."
vault kv get -field=tlscacerts "${VAULT_PATH}/users/admin-msp" >"${MSP_DIR}/tlscacerts/tlsca.pem"

# Copy admin cert to admincerts directory (required for older Fabric versions)
cp "${MSP_DIR}/signcerts/cert.pem" "${MSP_DIR}/admincerts/cert.pem"

# Export TLS certificates
echo ""
echo "Exporting TLS certificates..."

echo "  - Fetching TLS CA certificate..."
vault kv get -field=cacert "${VAULT_PATH}/users/admin-tls" >"${TLS_DIR}/ca.crt"

echo "  - Fetching TLS client certificate..."
vault kv get -field=clientcert "${VAULT_PATH}/users/admin-tls" >"${TLS_DIR}/client.crt"

echo "  - Fetching TLS client key..."
vault kv get -field=clientkey "${VAULT_PATH}/users/admin-tls" >"${TLS_DIR}/client.key"

# Set appropriate permissions
echo ""
echo "Setting file permissions..."
chmod 700 "${ORG_DIR}" "${MSP_DIR}" "${TLS_DIR}"
chmod 600 "${MSP_DIR}/keystore/key.pem" "${TLS_DIR}/client.key"
chmod 644 "${MSP_DIR}"/{signcerts,cacerts,tlscacerts,admincerts}/*.pem
chmod 644 "${TLS_DIR}"/{ca.crt,client.crt}

echo ""
echo "Certificates exported to ${ORG_DIR}/"
echo "  - MSP: ${MSP_DIR}"
echo "  - TLS: ${TLS_DIR}"
echo ""
echo "Directory structure:"
tree "${ORG_DIR}" 2>/dev/null || find "${ORG_DIR}" -type f

echo ""
echo "Export complete!"
```

### Run the Export Script

First, update the configuration variables in the script:
- `ORG_NAME`: Your organization name
- `VAULT_PATH`: The Vault path where your org's certificates are stored
- `VAULT_ADDR`: Your Vault URL

Then execute:

```bash
chmod +x export-org-msp.sh
./export-org-msp.sh
```

## Part 5: Configuring Fabconnect with Exported MSP

### Fabconnect Configuration

Create or update your Fabconnect configuration file:

```yaml
# fabconnect-config.yaml
organizations:
  <org-name>:
    mspid: <org-name>MSP  # e.g., ombud2MSP, carrierMSP
    
    # Path to the exported MSP directory
    mspconfigpath: /path/to/<org-name>/msp
    
    # TLS settings
    tlscacerts: /path/to/<org-name>/tls/ca.crt
    
peers:
  peer0.<org-name>:
    url: grpcs://peer0.<org-name>-net.<your-domain>:443
    tlscacerts: /path/to/<org-name>/msp/tlscacerts/tlsca.pem
    grpcOptions:
      ssl-target-name-override: peer0.<org-name>-net
      grpc.keepalive_time_ms: 600000
```

### Docker Compose Example for Fabconnect

```yaml
version: '3.7'

services:
  fabconnect:
    image: ghcr.io/hyperledger/firefly-fabconnect:latest
    ports:
      - "3000:3000"
    volumes:
      - ./<org-name>/msp:/fabconnect/msp:ro
      - ./<org-name>/tls:/fabconnect/tls:ro
      - ./fabconnect-config.yaml:/fabconnect/config.yaml:ro
    environment:
      - FABCONNECT_CONFIGPATH=/fabconnect/config.yaml
      - FABCONNECT_ORGNAME=<org-name>
      - FABCONNECT_MSPID=<org-name>MSP
      - FABCONNECT_MSPCONFIG=/fabconnect/msp
```

## Part 6: Verification

### Verify MSP and TLS Structure

```bash
# Check that all required files exist
ls -lR <org-name>/

# Verify MSP certificate validity
openssl x509 -in <org-name>/msp/signcerts/cert.pem -text -noout | grep -E "Subject:|Issuer:|Not"

# Verify MSP private key
openssl ec -in <org-name>/msp/keystore/key.pem -check -noout

# Verify TLS certificate validity
openssl x509 -in <org-name>/tls/client.crt -text -noout | grep -E "Subject:|Issuer:|Not"

# Verify TLS private key
openssl ec -in <org-name>/tls/client.key -check -noout
```

### Test Connection from External Device

If you have Fabric peer CLI installed:

```bash
export FABRIC_CFG_PATH=/path/to/config
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID="<org-name>MSP"
export CORE_PEER_TLS_ROOTCERT_FILE=/path/to/<org-name>/msp/tlscacerts/tlsca.pem
export CORE_PEER_MSPCONFIGPATH=/path/to/<org-name>/msp
export CORE_PEER_ADDRESS=peer0.<org-name>-net.<your-domain>:443

# Create minimal core.yaml with BCCSP config
cat > core.yaml << EOF
peer:
  BCCSP:
    Default: SW
    SW:
      Hash: SHA2
      Security: 256
EOF

# Test query
peer lifecycle chaincode queryinstalled
```

## Part 7: Security Best Practices

1. **Secure the Exported Certificates:**
   ```bash
   # Create encrypted archive for both MSP and TLS
   tar -czf <org-name>-certs.tar.gz <org-name>/
   gpg -c <org-name>-certs.tar.gz
   rm <org-name>-certs.tar.gz
   ```

2. **Use Environment Variables for Vault Token:**
   ```bash
   # Never hardcode tokens in scripts
   export VAULT_TOKEN=$(cat ~/.vault-token)
   ```

3. **Restrict File Permissions:**
   ```bash
   chmod 700 <org-name> <org-name>/msp <org-name>/tls
   chmod 600 <org-name>/msp/keystore/* <org-name>/tls/client.key
   ```

4. **Use TLS for Vault Access:**
   - In production, always use HTTPS for Vault
   - Consider mutual TLS authentication

5. **Rotate Certificates Regularly:**
   - Re-export certificates when they're rotated
   - Monitor certificate expiration dates

## Troubleshooting

### Cannot Connect to Vault
```bash
# Check network connectivity
curl -v http://<vault-host-ip>:8200/v1/sys/health

# Verify Vault status
vault status -address=http://<vault-host-ip>:8200

# If using SSH tunnel, ensure the tunnel is active
ps aux | grep "ssh -L 8200"
```

### Invalid Token
```bash
# Check token validity
vault token lookup

# Get new token from cluster admin if expired
```

### Certificate Validation Errors
```bash
# Verify certificate format
file <org-name>/msp/signcerts/cert.pem  # Should be "PEM certificate"

# Check for encoding issues
dos2unix <org-name>/msp/**/*.pem <org-name>/tls/**/*.{crt,key}  # If files came from Windows
```

### Missing Fields in Vault
```bash
# List available fields
vault kv get ${VAULT_PATH}/users/admin-msp

# Check Vault path
vault kv list ${VAULT_PATH}/users/
```

## Additional Resources

- **Fabric MSP Documentation:** https://hyperledger-fabric.readthedocs.io/en/latest/msp.html
- **Fabconnect Documentation:** https://github.com/hyperledger/firefly-fabconnect
- **Vault KV Secrets Engine:** https://www.vaultproject.io/docs/secrets/kv

## Summary

You now have:
1. ✅ Vault access configured from external device
2. ✅ Complete MSP directory structure exported
3. ✅ TLS certificates exported for secure communication
4. ✅ Certificates ready for Fabconnect integration
5. ✅ Verification steps completed

The exported MSP and TLS certificates can now be mounted in your Fabconnect container or referenced in your Firefly configuration.
