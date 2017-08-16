#
# PostgreSQL Dockerfile on CentOS 7
#

# Build:
# docker build -t zokeber/postgresql:latest .
#
# Create:
# docker create -it -p 5432:5432 --name postgresql94 zokeber/postgresql
#
# Start:
# docker start postgresql94
#
# Connect with postgresql client
# docker exec -it postgresql94 psql
#
# Connect bash
# docker exec -it postgresql94 bash


# Pull base image
FROM zokeber/centos:latest

# Maintener
MAINTAINER Paolo Lizarazu <polochepu@gmail.com>

# Postgresql version
ENV PG_VERSION 9.6
ENV PGVERSION 96

# Set the environment variables
ENV HOME /var/lib/pgsql
ENV PGDATA /var/lib/pgsql/9.6/data


# Upgrading system
RUN yum -y upgrade
RUN yum -y install wget

# Install postgresql and run InitDB
#RUN wget "https://download.postgresql.org/pub/repos/yum/$PG_VERSION/redhat/rhel-7-x86_64/pgdg-centos$PGVERSION-$PG_VERSION-3.noarch.rpm" -O /tmp/postgresql$PGVERSION.rpm
#RUN ls /tmp/
#RUN yum install -y /tmp/postgresql$PGVERSION.rpm
#RUN yum install -y sudo pwgen 



#RUN yum update -y
RUN rpm -vih https://download.postgresql.org/pub/repos/yum/$PG_VERSION/redhat/rhel-7-x86_64/pgdg-centos$PGVERSION-$PG_VERSION-3.noarch.rpm && \
    yum update -y && \
    yum install -y sudo \
    pwgen \
    epel-release \
    xmlstarlet \
    saxon \
    augeas \
    bsdtar \
    unzip \
    jq \
    postgresql$PGVERSION \
    postgresql$PGVERSION-server \
    postgresql$PGVERSION-contrib && \
    yum clean all

# Copy
COPY data/postgresql-setup /usr/pgsql-$PG_VERSION/bin/postgresql$PGVERSION-setup

# Working directory
WORKDIR /var/lib/pgsql

# Run initdb
RUN /usr/pgsql-$PG_VERSION/bin/postgresql$PGVERSION-setup initdb

# Copy config file
COPY data/postgresql.conf /var/lib/pgsql/$PG_VERSION/data/postgresql.conf
COPY data/pg_hba.conf /var/lib/pgsql/$PG_VERSION/data/pg_hba.conf
COPY data/postgresql.sh /usr/local/bin/postgresql.sh

# Change own user
RUN chown -R postgres:postgres /var/lib/pgsql/$PG_VERSION/data/* && \
    usermod -G wheel postgres && \
    sed -i 's/.*requiretty$/#Defaults requiretty/' /etc/sudoers && \
    chmod +x /usr/local/bin/postgresql.sh

# Set volume
VOLUME ["/var/lib/pgsql"]

# Set username
USER postgres

# Expose ports.
EXPOSE 5432

#####################################################
##########   INSTALLING JAVA JDK  ###################
#####################################################
ENV JAVA_VERSION 8u144
ENV BUILD_VERSION b01



# Downloading Java
RUN wget --no-cookies --no-check-certificate --header "Cookie: oraclelicense=accept-securebackup-cookie" "http://download.oracle.com/otn-pub/java/jdk/$JAVA_VERSION-$BUILD_VERSION/090f390dda5b47b9b721c7dfaa008135/jdk-$JAVA_VERSION-linux-x64.rpm" -O /tmp/jdk-8-linux-x64.rpm
USER root
RUN yum -y install /tmp/jdk-8-linux-x64.rpm


RUN alternatives --install /usr/bin/java jar /usr/java/latest/bin/java 200000
RUN alternatives --install /usr/bin/javaws javaws /usr/java/latest/bin/javaws 200000
RUN alternatives --install /usr/bin/javac javac /usr/java/latest/bin/javac 200000
RUN mkdir /opt/jboss 
WORKDIR /opt/jboss

ADD start.sh /opt/jboss/start.sh
RUN chmod +x /opt/jboss/start.sh

ADD docker-entrypoint.sh /opt/jboss/
RUN chmod +x /opt/jboss/docker-entrypoint.sh
RUN chown -R postgres:postgres /opt/jboss


USER postgres
ENV JAVA_HOME /usr/java/latest
#####################################################
##########   INSTALLING KEYCLOAK  ###################
#####################################################

# Create a user and group used to launch processes
# The user ID 1000 is the default for the first "regular" user on Fedora/RHEL,
# so there is a high chance that this ID will be equal to the current user
# making it easier to use volumes (no permission issues)

#RUN groupadd -r jboss -g 1000 && useradd -u 1000 -r -g jboss -m -d /opt/jboss -s /sbin/nologin -c "JBoss user" jboss && \
#    chmod 777 /opt/jboss

# Set the working directory to jboss' user home directory


# Specify the user which should be used to execute all commands below
#USER jboss

ENV KEYCLOAK_VERSION 3.2.1.Final
# Enables signals getting passed from startup script to JVM
# ensuring clean shutdown when container is stopped.
ENV LAUNCH_JBOSS_IN_BACKGROUND 1
ENV PROXY_ADDRESS_FORWARDING false

ENV JAVA_HOME /usr/java/latest

RUN cd /opt/jboss/ && curl -L https://downloads.jboss.org/keycloak/$KEYCLOAK_VERSION/keycloak-$KEYCLOAK_VERSION.tar.gz | tar zx && mv /opt/jboss/keycloak-$KEYCLOAK_VERSION /opt/jboss/keycloak


RUN ls -la /opt/jboss/keycloak/standalone/configuration/
ADD setLogLevel.xsl /opt/jboss/keycloak/
RUN /usr/java/latest/bin/java -jar /usr/share/java/saxon.jar -s:/opt/jboss/keycloak/standalone/configuration/standalone.xml -xsl:/opt/jboss/keycloak/setLogLevel.xsl -o:/opt/jboss/keycloak/standalone/configuration/standalone.xml

RUN /opt/jboss/keycloak/bin/add-user-keycloak.sh -u admin -p plc-kc-pass
ENV JBOSS_HOME /opt/jboss/keycloak

#Enabling Proxy address forwarding so we can correctly handle SSL termination in front ends
#such as an OpenShift Router or Apache Proxy
RUN sed -i -e 's/<http-listener /& proxy-address-forwarding="${env.PROXY_ADDRESS_FORWARDING}" /' $JBOSS_HOME/standalone/configuration/standalone.xml

EXPOSE 8080




#####################################################
##########   CONFIGURING KEYCLOAK-POSTGRES ##########
#####################################################

ADD keycloak/changeDatabase.xsl /opt/jboss/keycloak/
RUN /usr/java/latest/bin/java -jar /usr/share/java/saxon.jar -s:/opt/jboss/keycloak/standalone/configuration/standalone.xml -xsl:/opt/jboss/keycloak/changeDatabase.xsl -o:/opt/jboss/keycloak/standalone/configuration/standalone.xml; /usr/java/latest/bin/java -jar /usr/share/java/saxon.jar -s:/opt/jboss/keycloak/standalone/configuration/standalone-ha.xml -xsl:/opt/jboss/keycloak/changeDatabase.xsl -o:/opt/jboss/keycloak/standalone/configuration/standalone-ha.xml; rm /opt/jboss/keycloak/changeDatabase.xsl
RUN mkdir -p /opt/jboss/keycloak/modules/system/layers/base/org/postgresql/jdbc/main; cd /opt/jboss/keycloak/modules/system/layers/base/org/postgresql/jdbc/main; curl -O http://central.maven.org/maven2/org/postgresql/postgresql/9.3-1102-jdbc3/postgresql-9.3-1102-jdbc3.jar
ADD keycloak/module.xml /opt/jboss/keycloak/modules/system/layers/base/org/postgresql/jdbc/main/



ENTRYPOINT ["/opt/jboss/start.sh"]