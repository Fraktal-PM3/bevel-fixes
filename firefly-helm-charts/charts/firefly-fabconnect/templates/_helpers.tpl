{{/*
  Copyright © 2024 Kaleido, Inc.

  SPDX-License-Identifier: Apache-2.0

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

  http://swww.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "firefly-fabconnect.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "firefly-fabconnect.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "firefly-fabconnect.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "firefly-fabconnect.labels" -}}
helm.sh/chart: {{ include "firefly-fabconnect.chart" . }}
{{ include "firefly-fabconnect.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "firefly-fabconnect.selectorLabels" -}}
app.kubernetes.io/name: {{ include "firefly-fabconnect.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: fabconnect
{{- end }}

{{/*
Generate the FabConnect configuration YAML
*/}}
{{- define "firefly-fabconnect.config" -}}
{{- if .Values.config.templateOverride }}
{{- tpl .Values.config.templateOverride . }}
{{- else }}
maxinflight: {{ .Values.config.maxInFlight }}
maxtxwaittime: {{ .Values.config.maxTXWaitTime }}
sendconcurrency: {{ .Values.config.sendConcurrency }}

receipts:
  maxdocs: {{ .Values.config.receipts.maxDocs }}
  querylimit: {{ .Values.config.receipts.queryLimit }}
  retryinitialdelay: {{ .Values.config.receipts.retryInitialDelay }}
  retrytimeout: {{ .Values.config.receipts.retryTimeout }}
  leveldb:
    path: {{ .Values.config.receipts.leveldb.path }}

events:
  webhooksAllowPrivateIPs: {{ .Values.config.webhooksAllowPrivateIPs }}
  leveldb:
    path: {{ .Values.config.events.leveldb.path }}

http:
  port: {{ .Values.config.port }}

rpc:
  configpath: {{ .Values.config.rpc.configPath }}

{{- if .Values.log.fabricSDKDebug }}
# Enable Fabric SDK debug logging
log:
  level: {{ .Values.log.level }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Generate the Fabric Connection Profile (CCP) YAML
*/}}
{{- define "firefly-fabconnect.connectionProfile" -}}
{{- if .Values.connectionProfile.autoGenerate }}
version: 1.1.0

client:
  organization: {{ .Values.fabric.organizationName }}
  logging:
    level: {{ .Values.log.level }}
  BCCSP:
    security:
      enabled: true
      default:
        provider: SW
      hashAlgorithm: SHA2
      softVerify: true
      level: 256
  credentialStore:
    path: {{ .Values.msp.mountPath }}/msp
    cryptoStore:
      path: {{ .Values.msp.mountPath }}/msp
  cryptoconfig:
    path: {{ .Values.msp.mountPath }}/msp
  tlsCerts:
    client:
      cert:
        path: {{ .Values.msp.mountPath }}/msp/users/admin/msp/signcerts/cert.pem
      key:
        path: {{ .Values.msp.mountPath }}/msp/users/admin/msp/keystore/key.pem

organizations:
  {{ .Values.fabric.organizationName }}:
    mspid: {{ .Values.fabric.organizationMspId }}
    cryptoPath: /tmp/msp
    peers:
      - {{ .Values.fabric.organizationName }}_peer
    certificateAuthorities:
      - {{ .Values.fabric.organizationName }}_ca
    users:
      {{ .Values.fabric.organizationName | replace "-net" "" }}:
        cert:
          path: {{ .Values.msp.mountPath }}/msp/users/admin/msp/signcerts/cert.pem
        key:
          path: {{ .Values.msp.mountPath }}/msp/users/admin/msp/keystore/key.pem
      Admin@{{ .Values.fabric.organizationName }}:
        cert:
          path: {{ .Values.msp.mountPath }}/msp/users/admin/msp/signcerts/cert.pem
        key:
          path: {{ .Values.msp.mountPath }}/msp/users/admin/msp/keystore/key.pem

peers:
  {{ .Values.fabric.organizationName }}_peer:
    url: {{ .Values.fabric.peerUrl }}
    tlsCACerts:
      path: {{ .Values.msp.mountPath }}/msp/tlscacerts/tlsca.pem

orderers:
  {{ .Values.fabric.organizationName }}_orderer:
    url: {{ .Values.fabric.ordererUrl }}
    tlsCACerts:
      path: {{ .Values.msp.mountPath }}/msp/tlscacerts/tlsca.pem

certificateAuthorities:
  {{ .Values.fabric.organizationName }}_ca:
    url: {{ .Values.fabric.caUrl }}
    tlsCACerts:
      path: {{ .Values.msp.mountPath }}/msp/cacerts/ca.pem
    registrar:
      enrollId: {{ .Values.fabric.enrollId }}
      enrollSecret: {{ .Values.fabric.enrollSecret }}

channels:
  {{ .Values.fabric.channelName }}:
    peers:
      {{ .Values.fabric.organizationName }}_peer:
        endorsingPeer: true
        chaincodeQuery: true
        ledgerQuery: true
        eventSource: true
    orderers:
      - {{ .Values.fabric.organizationName }}_orderer
{{- else }}
{{- tpl .Values.connectionProfile.customProfile . }}
{{- end }}
{{- end }}
