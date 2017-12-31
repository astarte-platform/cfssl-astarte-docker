#!/bin/bash

set -e

# Copy eventual overrides
cp /config/* /etc/cfssl/ || true

# Generate keys if necessary
if [ ! -f /etc/cfssl/ca.pem ] || [ ! -f /etc/cfssl/ca-key.pem ] ; then
    # Create root
    cd /etc/cfssl
    cfssl gencert -initca "/etc/cfssl/csr_root_ca.json" | cfssljson -bare ca
    cd -
fi

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

exec "$@"