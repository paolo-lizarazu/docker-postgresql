#!/bin/bash

# Start the first process
/usr/local/bin/postgresql.sh start &

# Start the second process
/opt/jboss/docker-entrypoint.sh -b 0.0.0.0 &

