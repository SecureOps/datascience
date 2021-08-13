# Data Science tools/environment
Various DevOps build definitions used for other data management projects.

# Wazuh
Reference the [Wazuh Architecture](https://documentation.wazuh.com/current/getting-started/architecture.html) page for more details.

## Architecture
The helm chart launches pods as depicted in this [diagram](https://documentation.wazuh.com/current/_images/deployment1.png) provided by the Wazuh project:
![Wazuh Architecture Image](https://documentation.wazuh.com/current/_images/deployment1.png)

\*The *master* pod has been renamed to **manager** for the sake of this project.

### Exceptions to this diagram:
The helm chart does not install the Kibana/ElasticSearch environment.

The *manager* pod does not accept Agent Endpoint connections (AuthD or Secure) and has for sole purpose to host the Wazuh API (TCP 55000) and the cluster management port (TCP1516).

The *Worker* pod(s) are responsible for Agent Endpoint connections (AuthD \[TCP1515] or Secure \[TCP1514]).

An optional *Agent* pod is available in case dedicated *Wodles* or pull-type actions (like GCP) would need to be performed by the cluster to acquire logs, although these may optionally be configured on the *manager* as well in most cases so the agent pod is **disabled** by default.

Note, no *syslog* mechanism has been exposed for the moment and would need to be implemented by an external agent.

## Installation
Launching the chart with no arguments creates a wazuh cluster with a manager pod and two worker pods and exposes the authd and secure agent communications port under a k8s service using TCP only.

### Agent Enrollment and authentication
In the default scenario, the agent enrollment must be keyed manually.

In order to enable agent auto-enrollment using a passphrase, set *wazuh.authd.agentPassphraseEnabled* to *true*. If *wazuh.authd.agentPassphrase* is specified, the chart will mount a k8s [secret](https://kubernetes.io/docs/reference/kubernetes-api/config-and-storage-resources/secret-v1/) that will inject the passphrase into the *worker* and *agent* pods. If *wazuh.authd.agentPasshphrase* is not provided, then the workers will use a random key and one must log into one of the *worker* pods in order to retrieve the value from */var/ossec/etc/authd.pass*.

In order to enable agent auto-enrollment using *X509* certificates, set *wazuh.authd.ssl_agent_ca_enabled* to *true*. This will automatically use the mounted TLS [secret](https://kubernetes.io/docs/reference/kubernetes-api/config-and-storage-resources/secret-v1/) cited [below](#TLS/SSL). Any agent presenting a certificate signed by the provided *rootCA.crt* will be accepted.

### Kibana integration
The provided docker image is a re-write of the [ODFE](https://hub.docker.com/r/amazon/opendistro-for-elasticsearch-kibana) Kibana container that installs plugins provided to the container via the KIBANA_PLUGINS_SPACE_DELIMITED environment variable.

The helm charts provided by [ODFE](https://opendistro.github.io/for-elasticsearch-docs/docs/install/helm/) can be overridden to load this image by providing the relevant *kibana.image* and *kibana.imageTag* values to point to a docker repository where the image is hosted.

A *wazuh user* must then be defined in order for **Filebeat** to be able to connect to the ElasticSearch cluster and create the *wazuh_* indexes.

In the kibana->Open Distro for ElasticSearch->Security panel, create a role with the following permissions:
```
cluster permissions:
  - cluster_monitor
  - cluster_composite_ops
  - indices:admin/template/get
  - indices:admin/template/put
  - cluster:admin/ingest/pipeline/get
  - cluster:admin/ingest/pipeline/put
index permissions (wazuh*):
  - crud
  - create_index
```

This role should then be assigned to the *internal user* used by filebeat. If **ODFE** is configured to use certificates, then the value of the *CN* or *common_name* attribute should be used, if not, then a pre-configured username/password should be created and passed to the filebeat configuration using *wazuh.filebeat.es_username* and *wazuh.worker.filebeat.es_password* in the *values.yaml* file of the wazuh helm chart.

## Helm values.yaml overrides
| Yaml Path | default | Function |
|:--------- | ------- | -------- |
| wazuh.cluster.enabled | true | If *false* will only launch the manager pod with no environment variables|
| wazuh.authd.enabled| true | If *false* it disables the authd functionality on workers |
|wazuh.authd.agentPassphraseEnabled | false | If *true*, causes the workers and agent to use *authd.pass* file for auto-enrollment|
|wazuh.authd.agentPassphrase | \<undefined> | will mount file containing the provided passphrase into the *worker* and *agent* pods|
|wazuh.authd.ssl_agent_ca_enabled | false | if *true* will use the certificates provided by the mounted *release_name*-authd-certs.wazuh-authd-root-ca.pem secret to validate agent client certificates|
| wazuh.filebeat.es_hosts | [] | JSON or YAML array with quotes strings with path to ES REST API cluster (port 9200)|
| wazuh.filebeat.es_username | \<undefined> | Username to connect to ES cluster, may not be required if certificates aren't used |
| wazuh.filebeat.es_password | \<undefined> | Password to connect to ES cluster, may not be required if certificates aren't used |

### TLS/SSL
Can be configured for each component by providing key/cert/cachain as an **Opaque** k8s [secret](https://kubernetes.io/docs/reference/kubernetes-api/config-and-storage-resources/secret-v1/).

Note, this installation **does not** generate any X509 certificates **for use with Wazuh** itself. The docker container generates self-signed certs for the **filebeat** component if they are not mounted.

The "data" portion of the secret always contains the PEM-encoded data for each as per this table:

| Component | Secret Name | Data Subpath | Mounts to |
| --------- |:-----------:|:------------:| ---------|
| API <sub>(Manager)</sub> | *release_name*-api-certs | wazuh-api-key.pem | /var/ossec/api/configuration/ssl/server.key |
| API <sub>(Manager)</sub> | *release_name*-api-certs | wazuh-api-cert.pem | /var/ossec/api/configuration/ssl/server.crt |
| API <sub>(Manager)</sub>| *release_name*-api-certs | wazuh-api-root-ca.pem | (not mounted but must be present) |
| AuthD <sub>(Worker)</sub>| *release_name*-authd-certs | wazuh-authd-key.pem | /var/ossec/etc/sslmanager.key |
| AuthD <sub>(Worker)</sub>| *release_name*-authd-certs | wazuh-authd-cert.pem | /var/ossec/etc/sslmanager.cert |
| AuthD <sub>(Worker)</sub>| *release_name*-authd-certs | wazuh-authd-root-ca.pem | /var/ossec/etc/rootCA.pem |
| AuthD <sub>(Agent)</sub>| *release_name*-agent-certs | wazuh-agent-key.pem | /var/ossec/etc/agent.key |
| AuthD <sub>(Agent)</sub>| *release_name*-agent-certs | wazuh-agent-cert.pem | /var/ossec/etc/agent.crt |
| AuthD <sub>(Agent)</sub>| *release_name*-agent-certs | wazuh-agent-root-ca.pem | /var/ossec/etc/rootCA.pem |
| Filebeat | *release_name*-filebeat-certs | filebeat-key.pem |  /etc/filebeat/certs/filebeat-key.pem |
| Filebeat | *release_name*-filebeat-certs | filebeat-cert.pem |  /etc/filebeat/certs/filebeat.pem |
| Filebeat| *release_name*-filebeat-certs | filebeat-root-ca.pem | /etc/filebeat/certs/root-ca.pem |

\* Note the mounted paths are the defaults or injected into the configuration by the docker container at runtime. These should not be changed without modifying the helm chart itself.



## TODO
- The Wazuh API service is not exposed with a k8s *service* or *ingress* at the moment. Kibana environment is required to be deployed on the same K8S cluster inside the same namespace in order to get the UI working.
- ES permissions for the Wazuh Filebeat user need to be implemented manually via the Kibana "management" UI.
- Fix the es_hosts to handle situations:
  - Only works right now as a YAML array of quoted strings
  - Provided as a "string" that is just the hostname (needs to quote and convert to JSON array)
  - Provided YAML array of unquoted strings
  - Provided JSON
- Test persistence of the various containers. Right now containers re-initialize completely each time they're rebooted
- Add provisions to allow for syslog service. This wasn't done because no encryption is supported at the moment.


# Resource materials
https://medium.com/@ibrahim.ayadhi/hello-and-welcome-to-our-new-article-which-will-be-covering-the-alerting-part-in-our-socaas-136cf6258c49
https://github.com/karql/elastalert-kibana-plugin
