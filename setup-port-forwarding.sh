#!/bin/bash
##############################################################################################
#  Copyright Accenture. All Rights Reserved.
#
#  SPDX-License-Identifier: Apache-2.0
##############################################################################################

# Script to set up port forwarding from host to minikube for HAProxy ingress
# This enables external access to the Kubernetes cluster via the public IP

set -e

# Configuration
PUBLIC_IP="46.62.234.169"
MINIKUBE_IP="192.168.49.2"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Minikube HAProxy Port Forwarding Setup${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Error: This script must be run as root${NC}"
  echo "Please run: sudo $0"
  exit 1
fi

# Check if minikube is running
echo -e "${YELLOW}Checking if minikube is running...${NC}"
if ! su - hedlund01 -c "minikube status" > /dev/null 2>&1; then
  echo -e "${RED}Error: Minikube is not running${NC}"
  echo "Please start minikube first: minikube start"
  exit 1
fi
echo -e "${GREEN}✓ Minikube is running${NC}"
echo ""

# Install socat if not present
echo -e "${YELLOW}Checking for socat...${NC}"
if ! command -v socat &> /dev/null; then
  echo "Installing socat..."
  apt-get update -qq && apt-get install -y socat
  echo -e "${GREEN}✓ Socat installed${NC}"
else
  echo -e "${GREEN}✓ Socat is already installed${NC}"
fi
echo ""

# Stop existing socat processes if any
echo -e "${YELLOW}Stopping any existing port forwarding processes...${NC}"
if [ -f /var/run/socat-http.pid ]; then
  kill $(cat /var/run/socat-http.pid) 2>/dev/null || true
  rm -f /var/run/socat-http.pid
fi
if [ -f /var/run/socat-https.pid ]; then
  kill $(cat /var/run/socat-https.pid) 2>/dev/null || true
  rm -f /var/run/socat-https.pid
fi
pkill -f "socat.*$PUBLIC_IP" 2>/dev/null || true
echo -e "${GREEN}✓ Cleaned up old processes${NC}"
echo ""

# Start port forwarding with socat
echo -e "${YELLOW}Setting up port forwarding...${NC}"
echo "  HTTP:  $PUBLIC_IP:80  -> $MINIKUBE_IP:80"
echo "  HTTPS: $PUBLIC_IP:443 -> $MINIKUBE_IP:443"

# Forward HTTP (80)
nohup socat TCP4-LISTEN:80,bind=$PUBLIC_IP,fork,reuseaddr TCP4:$MINIKUBE_IP:80 > /var/log/socat-http.log 2>&1 &
echo $! > /var/run/socat-http.pid
sleep 1

# Forward HTTPS (443)  
nohup socat TCP4-LISTEN:443,bind=$PUBLIC_IP,fork,reuseaddr TCP4:$MINIKUBE_IP:443 > /var/log/socat-https.log 2>&1 &
echo $! > /var/run/socat-https.pid
sleep 1

echo -e "${GREEN}✓ Port forwarding started${NC}"
echo "  HTTP PID:  $(cat /var/run/socat-http.pid)"
echo "  HTTPS PID: $(cat /var/run/socat-https.pid)"
echo ""

# Create systemd services for permanent setup
echo -e "${YELLOW}Creating systemd services for automatic startup...${NC}"

cat > /etc/systemd/system/minikube-haproxy-forward-http.service << EOF
[Unit]
Description=Port forwarding from host to minikube HAProxy ingress (HTTP)
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/socat TCP4-LISTEN:80,bind=$PUBLIC_IP,fork,reuseaddr TCP4:$MINIKUBE_IP:80
Restart=always
RestartSec=5
StandardOutput=append:/var/log/socat-http.log
StandardError=append:/var/log/socat-http.log

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/minikube-haproxy-forward-https.service << EOF
[Unit]
Description=Port forwarding from host to minikube HAProxy ingress (HTTPS)
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/socat TCP4-LISTEN:443,bind=$PUBLIC_IP,fork,reuseaddr TCP4:$MINIKUBE_IP:443
Restart=always
RestartSec=5
StandardOutput=append:/var/log/socat-https.log
StandardError=append:/var/log/socat-https.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable minikube-haproxy-forward-http.service minikube-haproxy-forward-https.service
echo -e "${GREEN}✓ Systemd services created and enabled${NC}"
echo ""

# Verify the setup
echo -e "${YELLOW}Verifying port forwarding...${NC}"
sleep 2

if ss -tlnp | grep "$PUBLIC_IP:80" > /dev/null; then
  echo -e "${GREEN}✓ HTTP (80) is listening on $PUBLIC_IP${NC}"
else
  echo -e "${RED}✗ HTTP (80) is NOT listening${NC}"
fi

if ss -tlnp | grep "$PUBLIC_IP:443" > /dev/null; then
  echo -e "${GREEN}✓ HTTPS (443) is listening on $PUBLIC_IP${NC}"
else
  echo -e "${RED}✗ HTTPS (443) is NOT listening${NC}"
fi
echo ""

# Test connectivity
echo -e "${YELLOW}Testing connectivity...${NC}"
if curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 5 https://ca.pm3org-net.pm3fraktal.se > /dev/null 2>&1; then
  echo -e "${GREEN}✓ Successfully connected to CA via HTTPS${NC}"
else
  echo -e "${YELLOW}⚠ Could not connect to CA (this may be normal if CA is not running yet)${NC}"
fi
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Port Forwarding Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "The following services are now running:"
echo "  • socat HTTP forwarding  (PID: $(cat /var/run/socat-http.pid))"
echo "  • socat HTTPS forwarding (PID: $(cat /var/run/socat-https.pid))"
echo ""
echo "Systemd services enabled for automatic startup on boot:"
echo "  • minikube-haproxy-forward-http.service"
echo "  • minikube-haproxy-forward-https.service"
echo ""
echo "Logs are available at:"
echo "  • /var/log/socat-http.log"
echo "  • /var/log/socat-https.log"
echo ""
echo "To check status:"
echo "  systemctl status minikube-haproxy-forward-http.service"
echo "  systemctl status minikube-haproxy-forward-https.service"
echo ""
echo "To stop port forwarding:"
echo "  systemctl stop minikube-haproxy-forward-http.service"
echo "  systemctl stop minikube-haproxy-forward-https.service"
echo ""
echo "To test the setup:"
echo "  curl -k https://ca.pm3org-net.pm3fraktal.se"
echo ""
