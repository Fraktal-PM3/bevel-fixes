#!/bin/bash
##############################################################################################
#  Copyright Accenture. All Rights Reserved.
#
#  SPDX-License-Identifier: Apache-2.0
##############################################################################################

set -e

echo "=========================================="
echo "Starting Network Reset Process"
echo "=========================================="

echo "Adding env variables..."
export PATH=/root/bin:$PATH

# Path to k8s config file
export KUBECONFIG=/home/hedlund01/bevel-fixes/build/config

# Cleanup FireFly deployments first (if they exist)
echo "=========================================="
echo "Cleaning up FireFly deployments..."
echo "=========================================="

if [ -f "/home/hedlund01/bevel-fixes/platforms/firefly/configuration/cleanup-firefly.yaml" ]; then
  ansible-playbook -vv /home/hedlund01/bevel-fixes/platforms/firefly/configuration/cleanup-firefly.yaml \
    --inventory-file=/home/hedlund01/bevel-fixes/platforms/shared/inventory/ \
    -e "@/home/hedlund01/bevel-fixes/build/network.yaml" \
    -e 'ansible_python_interpreter=/usr/bin/python3' || true

  echo "FireFly cleanup completed"
else
  echo "FireFly cleanup playbook not found, skipping..."
fi

# echo "=========================================="
# echo "Resetting Fabric Network..."
# echo "=========================================="

# exec ansible-playbook -vv /home/hedlund01/bevel-fixes/platforms/shared/configuration/site.yaml \
#   --inventory-file=/home/hedlund01/bevel-fixes/platforms/shared/inventory/ \
#   -e "@/home/hedlund01/bevel-fixes/build/network.yaml" \
#   -e 'ansible_python_interpreter=/usr/bin/python3' \
#   -e "reset='true'"
