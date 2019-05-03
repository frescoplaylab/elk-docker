# Dockerfile for ELK stack
# Elasticsearch, Logstash, Kibana 6.7.0

# Build with:
# docker build -t <repo-user>/elk .

# Run with:
# docker run -p 8000:8000 -p 9200:9200 -p 5044:5044 -it --name elk elk

FROM ubuntu:16.04


###############################################################################
#                                INSTALLATION
###############################################################################

### install prerequisites (cURL, gosu, JDK, tzdata)

ENV GOSU_VERSION 1.10

ARG DEBIAN_FRONTEND=noninteractive
RUN set -x \
 && apt-get update -qq \
 && apt-get install -qqy --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/* \
 && curl -L -o /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture)" \
 && curl -L -o /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture).asc" \
 && export GNUPGHOME="$(mktemp -d)" \
 && gpg --keyserver hkp://ha.pool.sks-keyservers.net:80 --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
 && gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
 && rm -r "$GNUPGHOME" /usr/local/bin/gosu.asc \
 && chmod +x /usr/local/bin/gosu \
 && gosu nobody true \
 && apt-get update -qq \
 && apt-get install -qqy --no-install-recommends openjdk-8-jdk tzdata sudo\
 && apt-get clean \
 && set +x

ENV JAVA_HOME /usr/lib/jvm/java-8-openjdk-amd64/jre


ENV ELK_VERSION 5.6.16

### install Elasticsearch

ENV ES_VERSION ${ELK_VERSION}
ENV ES_HOME /opt/elasticsearch
ENV ES_PACKAGE elasticsearch-${ES_VERSION}.tar.gz
ENV ES_GID 991
ENV ES_UID 991
ENV ES_PATH_CONF /etc/elasticsearch
ENV ES_PATH_BACKUP /var/backups

RUN groupadd -r user && useradd --no-log-init -r -g user user
RUN echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
USER user 

RUN sudo mkdir ${ES_HOME} \
 && sudo curl -O https://artifacts.elastic.co/downloads/elasticsearch/${ES_PACKAGE} \
 && sudo tar xzf ${ES_PACKAGE} -C ${ES_HOME} --strip-components=1 \
 && sudo rm -f ${ES_PACKAGE} \
 && sudo groupadd -r elasticsearch -g ${ES_GID} \
 && sudo useradd -r -s /usr/sbin/nologin -M -c "Elasticsearch service user" -u ${ES_UID} -g elasticsearch elasticsearch \
 && sudo mkdir -p /var/log/elasticsearch ${ES_PATH_CONF} ${ES_PATH_CONF}/scripts /var/lib/elasticsearch ${ES_PATH_BACKUP} \
 && sudo chown -R elasticsearch:elasticsearch ${ES_HOME} /var/log/elasticsearch /var/lib/elasticsearch ${ES_PATH_CONF} ${ES_PATH_BACKUP}


### install Logstash

ENV LOGSTASH_VERSION ${ELK_VERSION}
ENV LOGSTASH_HOME /opt/logstash
ENV LOGSTASH_PACKAGE logstash-${LOGSTASH_VERSION}.tar.gz
ENV LOGSTASH_GID 992
ENV LOGSTASH_UID 992
ENV LOGSTASH_PATH_CONF /etc/logstash
ENV LOGSTASH_PATH_SETTINGS ${LOGSTASH_HOME}/config

RUN sudo mkdir ${LOGSTASH_HOME} \
 && sudo curl -O https://artifacts.elastic.co/downloads/logstash/${LOGSTASH_PACKAGE} \
 && sudo tar xzf ${LOGSTASH_PACKAGE} -C ${LOGSTASH_HOME} --strip-components=1 \
 && sudo rm -f ${LOGSTASH_PACKAGE} \
 && sudo groupadd -r logstash -g ${LOGSTASH_GID} \
 && sudo useradd -r -s /usr/sbin/nologin -d ${LOGSTASH_HOME} -c "Logstash service user" -u ${LOGSTASH_UID} -g logstash logstash \
 && sudo mkdir -p /var/log/logstash ${LOGSTASH_PATH_CONF}/conf.d \
 && sudo chown -R logstash:logstash ${LOGSTASH_HOME} /var/log/logstash ${LOGSTASH_PATH_CONF}


### install Kibana

ENV KIBANA_VERSION ${ELK_VERSION}
ENV KIBANA_HOME /opt/kibana
ENV KIBANA_PACKAGE kibana-${KIBANA_VERSION}-linux-x86_64.tar.gz
ENV KIBANA_GID 993
ENV KIBANA_UID 993

RUN sudo mkdir ${KIBANA_HOME} \
 && sudo curl -O https://artifacts.elastic.co/downloads/kibana/${KIBANA_PACKAGE} \
 && sudo tar xzf ${KIBANA_PACKAGE} -C ${KIBANA_HOME} --strip-components=1 \
 && sudo rm -f ${KIBANA_PACKAGE} \
 && sudo groupadd -r kibana -g ${KIBANA_GID} \
 && sudo useradd -r -s /usr/sbin/nologin -d ${KIBANA_HOME} -c "Kibana service user" -u ${KIBANA_UID} -g kibana kibana \
 && sudo mkdir -p /var/log/kibana \
 && sudo chown -R kibana:kibana ${KIBANA_HOME} /var/log/kibana


###############################################################################
#                              START-UP SCRIPTS
###############################################################################

### Elasticsearch

ADD ./elasticsearch-init /etc/init.d/elasticsearch
RUN sudo sed -i -e 's#^ES_HOME=$#ES_HOME='$ES_HOME'#' /etc/init.d/elasticsearch \
 && sudo chmod +x /etc/init.d/elasticsearch

### Logstash

ADD ./logstash-init /etc/init.d/logstash
RUN sudo sed -i -e 's#^LS_HOME=$#LS_HOME='$LOGSTASH_HOME'#' /etc/init.d/logstash \
 && sudo chmod +x /etc/init.d/logstash

### Kibana

ADD ./kibana-init /etc/init.d/kibana
RUN sudo sed -i -e 's#^KIBANA_HOME=$#KIBANA_HOME='$KIBANA_HOME'#' /etc/init.d/kibana \
 && sudo chmod +x /etc/init.d/kibana


###############################################################################
#                               CONFIGURATION
###############################################################################

### configure Elasticsearch

ADD ./elasticsearch.yml ${ES_PATH_CONF}/elasticsearch.yml
ADD ./elasticsearch-default /etc/default/elasticsearch
RUN sudo cp ${ES_HOME}/config/log4j2.properties ${ES_HOME}/config/jvm.options \
    ${ES_PATH_CONF} \
 && sudo chown -R elasticsearch:elasticsearch ${ES_PATH_CONF} \
 && sudo chmod -R +r ${ES_PATH_CONF}

### configure Logstash



# pipelines
ADD pipelines.yml ${LOGSTASH_PATH_SETTINGS}/pipelines.yml

# filters
ADD ./02-beats-input.conf ${LOGSTASH_PATH_CONF}/conf.d/02-beats-input.conf
ADD ./10-syslog.conf ${LOGSTASH_PATH_CONF}/conf.d/10-syslog.conf
ADD ./11-nginx.conf ${LOGSTASH_PATH_CONF}/conf.d/11-nginx.conf
ADD ./30-output.conf ${LOGSTASH_PATH_CONF}/conf.d/30-output.conf

# patterns
ADD ./nginx.pattern ${LOGSTASH_HOME}/patterns/nginx
RUN sudo chown -R logstash:logstash ${LOGSTASH_HOME}/patterns

# Fix permissions
RUN sudo chmod -R +r ${LOGSTASH_PATH_CONF} ${LOGSTASH_PATH_SETTINGS} \
 && sudo chown -R logstash:logstash ${LOGSTASH_PATH_SETTINGS}

### configure logrotate

ADD ./elasticsearch-logrotate /etc/logrotate.d/elasticsearch
ADD ./logstash-logrotate /etc/logrotate.d/logstash
ADD ./kibana-logrotate /etc/logrotate.d/kibana
RUN sudo chmod 644 /etc/logrotate.d/elasticsearch \
 && sudo chmod 644 /etc/logrotate.d/logstash \
 && sudo chmod 644 /etc/logrotate.d/kibana


### configure Kibana

ADD ./kibana.yml ${KIBANA_HOME}/config/kibana.yml


###############################################################################
#                                   START
###############################################################################

ADD ./start.sh /usr/local/bin/start.sh
RUN sudo chmod +x /usr/local/bin/start.sh

# kibana running @8000
EXPOSE 8000 9200 9300 5044
VOLUME /var/lib/elasticsearch

CMD [ "/usr/local/bin/start.sh" ]
