#!/bin/bash
##############################################################################################
#  Copyright Accenture. All Rights Reserved.
#
#  SPDX-License-Identifier: Apache-2.0
##############################################################################################

set -e

echo "Starting chaincode installation process..."

echo "Adding env variables..."
export PATH=/root/bin:$PATH

# Path to k8s config file
export KUBECONFIG=/home/hedlund01/bevel-fixes/build/config

echo "Validating network yaml"
ajv validate -s /home/hedlund01/bevel-fixes/platforms/network-schema.json -d /home/hedlund01/bevel-fixes/build/network.yaml 

echo "Running chaincode operations playbook..."
exec ansible-playbook -vv /home/hedlund01/bevel-fixes/platforms/hyperledger-fabric/configuration/chaincode-ops.yaml --inventory-file=/home/hedlund01/bevel-fixes/platforms/shared/inventory/ -e "@/home/hedlund01/bevel-fixes/build/network.yaml" -e "add_new_org='false'" -e 'ansible_python_interpreter=/usr/bin/python3'
