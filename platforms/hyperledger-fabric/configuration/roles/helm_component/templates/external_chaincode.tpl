apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: cc-{{ chaincode_name }}
  namespace: {{ chaincode_ns }}
  annotations:
    fluxcd.io/automated: "false"
spec:
  interval: 1m
  releaseName: cc-{{ chaincode_name }}
  chart:
    spec:
      interval: 1m
      sourceRef:
        kind: GitRepository
        name: flux-{{ network.env.type }}
        namespace: flux-{{ network.env.type }}
      chart: {{ charts_dir }}/fabric-external-chaincode
  values:
    global:
      version: {{ network.version }}
      serviceAccountName: vault-auth
      cluster:
        provider: {{ org.cloud_provider }}
        cloudNativeServices: false
      vault:
        type: hashicorp
        address: {{ vault.url }}
        role: vault-role
        authPath: {{ network.env.type }}{{ org_name }}
        secretEngine: {{ vault.secret_path | default("secretsv2") }}
        secretPrefix: "data/{{ network.env.type }}{{ org_name }}"
        tls: false
      proxy:
        provider: {{ network.env.proxy | quote }}
        externalUrlSuffix: {{ org.external_url_suffix }}

    metadata:
      namespace: {{ chaincode_ns }}
      images:
        external_chaincode: {{ chaincode_image }}
        alpineutils: {{ docker_url }}/bevel-alpine:{{ bevel_alpine_version }}

    chaincode:
      name: {{ chaincode.name }}
      version: {{ chaincode.version }}
      ccid: {{ ccid.stdout | default('') | replace(',','') }}
      tls_disabled: {{ (not chaincode.tls) | lower }}
{% if chaincode.tls == true %}      
      crypto_mount_path: {{ chaincode.crypto_mount_path }}
{% endif %}

    vault:
      chaincodesecretprefix: {{ vault.secret_path | default('secretsv2') }}/data/{{ network.env.type }}{{ org.name | lower }}/chaincodes/secrets
{% if chaincode.private_registry is not defined or chaincode.private_registry == false %}   
      imagesecretname: regcred
{% endif %}
{% if chaincode.private_registry is defined and chaincode.private_registry == true %}   
      imagesecretname: chaincode-private-regcred
{% endif %}
    service:
      servicetype: ClusterIP

    certs:
      generateCertificates: {{ chaincode.tls | lower }}
      orgData:
{% if network.env.proxy == 'none' %}
        caAddress: ca.{{ namespace }}:7054
{% else %}
        caAddress: ca.{{ namespace }}.{{ org.external_url_suffix }}
{% endif %}
        caAdminUser: {{ org_name }}-admin
        caAdminPassword: {{ org_name }}-adminpw
        orgName: {{ org_name }}
        type: chaincode
        componentSubject: "{{ component_subject | quote }}"
      users:
        usersList:
          - user:
            identity: cc-{{ chaincode.name | lower | e }}
            attributes:

{% if network.env.labels is defined %}
    labels:
{% if network.env.labels.service is defined %}
      service:
{% for key in network.env.labels.service.keys() %}
        - {{ key }}: {{ network.env.labels.service[key] | quote }}
{% endfor %}
{% endif %}
{% if network.env.labels.pvc is defined %}
      pvc:
{% for key in network.env.labels.pvc.keys() %}
        - {{ key }}: {{ network.env.labels.pvc[key] | quote }}
{% endfor %}
{% endif %}
{% if network.env.labels.deployment is defined %}
      deployment:
{% for key in network.env.labels.deployment.keys() %}
        - {{ key }}: {{ network.env.labels.deployment[key] | quote }}
{% endfor %}
{% endif %}
{% endif %}
