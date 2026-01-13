#!/bin/bash
##############################################################################################
#  Copyright Accenture. All Rights Reserved.
#
#  SPDX-License-Identifier: Apache-2.0
##############################################################################################

set -e

echo "Starting build process..."

echo "Adding env variables..."
export PATH=/root/bin:$PATH

# Path to k8s config file
export KUBECONFIG=/home/hedlund01/bevel-fixes/build/config

echo "Validatin network yaml"
ajv validate -s /home/hedlund01/bevel-fixes/platforms/network-schema.json -d /home/hedlund01/bevel-fixes/build/network.yaml 

echo "Setting up External DNS credentials..."
bash /home/hedlund01/bevel-fixes/setup-external-dns.sh

echo "Running the playbook..."
exec ansible-playbook -vv /home/hedlund01/bevel-fixes/platforms/shared/configuration/site.yaml --inventory-file=/home/hedlund01/bevel-fixes/platforms/shared/inventory/ -e "@/home/hedlund01/bevel-fixes/build/network.yaml" -e 'ansible_python_interpreter=/usr/bin/python3'
