#!/bin/sh
set -e
#
# https://elastalert2.readthedocs.io/en/latest/elastalert.html#configuration
# https://github.com/Karql/elastalert
echo "Provided environment variables"
echo "ELASTALERT_PERSIST_RULES: ${ELASTALERT_PERSIST_RULES:-no}"
echo "ELASTALERT_CONFIG_USE_MOUNTED_VOLUME: ${ELASTALERT_CONFIG_USE_MOUNTED_VOLUME:-no}"
echo "ELASTALERT_ES_HOST: ${ELASTALERT_ES_HOST}"
echo "ELASTALERT_ES_TLS_ENABLED: ${ELASTALERT_ES_TLS_ENABLED:-no}"
echo "ELASTALERT_ES_CLIENT_VERIFY_CA: ${ELASTALERT_ES_CLIENT_VERIFY_CA:-no}"
echo "ELASTALERT_ES_USER: ${ELASTALERT_ES_USER}"

# Check if the directory is present, if it isn't link it
if [[ ! -d "/opt/elastalert/rule_templates" ]]; then
  echo "/opt/elastalert/rule_templates not found, linking it from /opt/elastalert/tmp/rule_templates"
  ln -s /opt/elastalert/tmp/rule_templates /opt/elastalert/rule_templates
fi

# Check if the directory is present, if it isn't link it
if [[ ! -d "/opt/elastalert-server/rule_templates" ]]; then
  echo "/opt/elastalert-server/rule_templates not found, linking it from /opt/elastalert/tmp/rule_templates"
  ln -s /opt/elastalert/tmp/rule_templates /opt/elastalert-server/rule_templates
fi

if [[ ! -e "/opt/elastalert-server/initialized" ]]; then
  # If the directory is present but not initialized, initialize it.
  echo "System not initialized..."
  if [[ ! -L "/opt/elastalert-server/rule_templates" && "$ELASTALERT_PERSIST_RULES" = 'yes' ]]; then
    echo "Persistent system not initialized"
    echo "Copying over /opt/elastalert/tmp/rule_templates to /opt/elastalert/rule_templates and /opt/elastalert-server/rule_templates"
    cp -a  /opt/elastalert/tmp/rule_templates/* /opt/elastalert/rule_templates
    cp -a  /opt/elastalert/tmp/rule_templates/* /opt/elastalert-server/rule_templates
  fi

  if [[ "$ELASTALERT_CONFIG_USE_MOUNTED_VOLUME" != 'yes' ]]; then
    echo "Using in-line config files, injecting variables..."
    # The configuration file isn't valid XML, we need to wrap it in root tags
    ELASTALERT_CONFIG_JSON=$(cat /opt/elastalert-server/config/config.json)
    if [[ "$ELASTALERT_ES_CLIENT_TLS_ENABLED" = 'yes' ]]; then
      echo "Turning on TLS for client ES communications"
      ELASTALERT_CONFIG_JSON=$(echo $ELASTALERT_CONFIG_JSON | jq '.es_ssl = true')
      yq w -i /opt/elastalert-server/config/elastalert.yaml "use_ssl" "True"
      yq w -i /opt/elastalert/config.yaml "use_ssl" "True"
      if [[ "$ELASTALERT_ES_CLIENT_VERIFY_CA" = 'yes' ]]; then
        echo "Turning on ES service TLS validation"
        yq w -i /opt/elastalert-server/config/elastalert.yaml "verify_certs" "True"
        yq w -i /opt/elastalert/config.yaml "verify_certs" "True"
        # es_ca_certs
        echo "Using CA certs from /opt/elastalert-server/config/client-chain.pem"
        ELASTALERT_CONFIG_JSON=$(echo $ELASTALERT_CONFIG_JSON | jq '.es_ca_certs = "/opt/elastalert-server/config/client-chain.pem"')
        yq w -i /opt/elastalert-server/config/elastalert.yaml "ca_certs" "/opt/elastalert-server/config/client-chain.pem"
        yq w -i /opt/elastalert/config.yaml "ca_certs" "/opt/elastalert-server/config/client-chain.pem"
      else
        echo "Turning off ES service TLS validation"
        yq w -i /opt/elastalert-server/config/elastalert.yaml "verify_certs" "False"
        yq w -i /opt/elastalert/config.yaml "verify_certs" "False"
        yq w -i /opt/elastalert-server/config/elastalert.yaml "ssl_show_warn" "False"
        yq w -i /opt/elastalert/config.yaml "ssl_show_warn" "False"
      fi
      # es_client_cert
      echo "Using client cert from /opt/elastalert-server/config/client-cert.pem"
      ELASTALERT_CONFIG_JSON=$(echo $ELASTALERT_CONFIG_JSON | jq '.es_client_cert = "/opt/elastalert-server/config/client-cert.pem"')
      yq w -i /opt/elastalert-server/config/elastalert.yaml "client_cert" "/opt/elastalert-server/config/client-cert.pem"
      yq w -i /opt/elastalert/config.yaml "client_cert" "/opt/elastalert-server/config/client-cert.pem"
      # es_client_key
      echo "Using client key from /opt/elastalert-server/config/client-key.pem"
      ELASTALERT_CONFIG_JSON=$(echo $ELASTALERT_CONFIG_JSON | jq '.es_client_key = "/opt/elastalert-server/config/client-key.pem"')
      yq w -i /opt/elastalert-server/config/elastalert.yaml "client_key" "/opt/elastalert-server/config/client-key.pem"
      yq w -i /opt/elastalert/config.yaml "client_key" "/opt/elastalert-server/config/client-key.pem"
    fi

    if [[ ! -z $ELASTALERT_ES_HOST ]]; then
      echo "Adding ${ELASTALERT_ES_HOST} to /opt/elastalert/config.yaml"
      ELASTALERT_CONFIG_JSON=$(echo $ELASTALERT_CONFIG_JSON | jq '.es_host = env.ELASTALERT_ES_HOST')
      yq w -i /opt/elastalert-server/config/elastalert.yaml "es_host" "${ELASTALERT_ES_HOST:-localhost}"
      yq w -i /opt/elastalert/config.yaml "es_host" "${ELASTALERT_ES_HOST:-localhost}"
    fi

    echo "Adding ${ELASTALERT_ES_PORT:-9200} to /opt/elastalert/config.yaml"
    if [[ ! -z $ELASTALERT_ES_PORT ]]; then
      ELASTALERT_CONFIG_JSON=$(echo $ELASTALERT_CONFIG_JSON | jq '.es_port = env.ELASTALERT_ES_PORT')
      yq w -i /opt/elastalert-server/config/elastalert.yaml "es_port" "${ELASTALERT_ES_PORT:-9200}"
      yq w -i /opt/elastalert/config.yaml "es_port" "${ELASTALERT_ES_PORT:-9200}"
    fi
  fi
  # Save the JSON file
  echo "${ELASTALERT_CONFIG_JSON}" > /opt/elastalert-server/config/config.json
  touch /opt/elastalert-server/initialized
else
  echo "This container has previously been initialized. To cause it to reset, please delete the file /var/ossec/etc/initialized"
fi

cd /opt/elastalert-server
exec npm start
