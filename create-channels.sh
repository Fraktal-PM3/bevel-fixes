#!/bin/bash
##############################################################################################
#  Copyright Accenture. All Rights Reserved.
#
#  SPDX-License-Identifier: Apache-2.0
##############################################################################################

set -e

echo "Starting channel creation and join process..."

echo "Adding env variables..."
export PATH=/root/bin:$PATH

# Path to k8s config file
export KUBECONFIG=/home/hedlund01/bevel-fixes/build/config

echo "Validating network yaml"
ajv validate -s /home/hedlund01/bevel-fixes/platforms/network-schema.json -d /home/hedlund01/bevel-fixes/build/network.yaml 

echo "Running create-join-channel playbook..."
exec ansible-playbook -vv /home/hedlund01/bevel-fixes/platforms/hyperledger-fabric/configuration/create-join-channel.yaml --inventory-file=/home/hedlund01/bevel-fixes/platforms/shared/inventory/ -e "@/home/hedlund01/bevel-fixes/build/network.yaml" -e 'ansible_python_interpreter=/usr/bin/python3'
