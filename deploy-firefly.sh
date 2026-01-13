#!/bin/bash
##############################################################################################
#  Copyright Accenture. All Rights Reserved.
#
#  SPDX-License-Identifier: Apache-2.0
##############################################################################################

set -e

echo "=========================================="
echo "Starting FireFly Deployment Process"
echo "=========================================="

echo "Adding environment variables..."
export PATH=/root/bin:$PATH

# Path to k8s config file
export KUBECONFIG=/home/hedlund01/bevel-fixes/build/config

echo "Validating network.yaml..."
ajv validate -s /home/hedlund01/bevel-fixes/platforms/network-schema.json \
  -d /home/hedlund01/bevel-fixes/build/network.yaml

if [ $? -ne 0 ]; then
  echo "ERROR: network.yaml validation failed"
  exit 1
fi

echo "Setting up External DNS credentials..."
if [ -f /home/hedlund01/bevel-fixes/setup-external-dns.sh ]; then
  bash /home/hedlund01/bevel-fixes/setup-external-dns.sh
fi

echo "=========================================="
echo "Running FireFly Deployment Playbook"
echo "=========================================="

exec ansible-playbook -vv /home/hedlund01/bevel-fixes/platforms/firefly/configuration/deploy-firefly.yaml \
  --inventory-file=/home/hedlund01/bevel-fixes/platforms/shared/inventory/ \
  -e "@/home/hedlund01/bevel-fixes/build/network.yaml" \
  -e 'ansible_python_interpreter=/usr/bin/python3'
