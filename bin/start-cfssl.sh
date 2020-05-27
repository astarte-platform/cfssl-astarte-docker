#!/bin/bash

set -e

CFSSL_CA_CERTIFICATE="${CFSSL_CA_CERTIFICATE:-/etc/cfssl/ca.pem}"
CFSSL_CA_PRIVATE_KEY="${CFSSL_CA_PRIVATE_KEY:-/etc/cfssl/ca-key.pem}"

# Copy eventual overrides
cp /config/* /etc/cfssl/ || true

# Generate keys if necessary, and if we're not on Kubernetes
if [[ -z "$KUBERNETES" ]]; then
    if [ ! -f $CFSSL_CA_CERTIFICATE ] || [ ! -f $CFSSL_CA_PRIVATE_KEY ] ; then
        # Do we have a persistent CA?
        if [ ! -f /data/ca.pem ] || [ ! -f /data/ca-key.pem ] ; then
            # Create root
            cd /data
            cfssl gencert -initca "/etc/cfssl/csr_root_ca.json" | cfssljson -bare ca
            cd -
            CFSSL_CA_CERTIFICATE="/data/ca.pem"
            CFSSL_CA_PRIVATE_KEY="/data/ca-key.pem"
        fi
    fi
fi

# Add the CA definitions
set -- "$@" -ca="$CFSSL_CA_CERTIFICATE" -ca-key="$CFSSL_CA_PRIVATE_KEY"

# Check whether we want to use a Database or not
if [[ -z "$CFSSL_USE_DB" ]]; then
    echo "Will start CFSSL without a Database"

    # Add config flags if cfssl
    if [ "${1}" = 'cfssl' ]; then
        set -- "$@" -config="/etc/cfssl/ca_root_config.json"
    fi
else
    echo "Will configure a CertDB for CFSSL"

    # Migrate database
    db_driver=$(cat /etc/cfssl/db_config.json | jq -r ".driver")
    db_data_source=$(cat /etc/cfssl/db_config.json | jq -r ".data_source")

    rm /usr/local/share/cfssl/certdb/$db_driver/dbconf.yml
    cat > /usr/local/share/cfssl/certdb/$db_driver/dbconf.yml <<EOF
production:
  driver: $db_driver
  open: $db_data_source
EOF

    goose -env production -path /usr/local/share/cfssl/certdb/$db_driver up

    # Add config flags if cfssl
    if [ "${1}" = 'cfssl' ]; then
        set -- "$@" -config="/etc/cfssl/ca_root_config.json" -db-config="/etc/cfssl/db_config.json"
    fi
fi

exec "$@"
