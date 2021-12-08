FROM praecoapp/elastalert-server:latest
RUN mkdir -p /opt/elastalert/tmp && mv /opt/elastalert/rule_templates /opt/elastalert/tmp && ln -s /opt/elastalert/tmp/rule_templates /opt/elastalert/rule_templates
RUN rm -rf /opt/elastalert-server/rule_templates && ln -s /opt/elastalert/tmp/rule_templates /opt/elastalert-server/rule_templates
USER root
RUN /sbin/apk add jq yq
ADD entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod a+x /usr/local/bin/docker-entrypoint.sh
USER node
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
