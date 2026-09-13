#!/bin/bash
# Copyright 2025 Rodericus Ifo Krista
# SPDX-License-Identifier: MIT

# Set the certificates directory
CERTS_DIR="certs"

# Services to generate certificates for, read from api.mk's APPLICATIONS
# variable (single source of truth for the service list).
# api-gateway gets a client certificate; the rest get server certificates.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_MK="$SCRIPT_DIR/../api.mk"

if [ ! -f "$API_MK" ]; then
    echo "Error: api.mk not found at $API_MK" >&2
    exit 1
fi

applications_line=$(grep -E '^APPLICATIONS[[:space:]]*:=' "$API_MK" | sed -E 's/^APPLICATIONS[[:space:]]*:=[[:space:]]*//')

if [ -z "$applications_line" ]; then
    echo "Error: APPLICATIONS variable not found in $API_MK" >&2
    exit 1
fi

read -ra SERVICES <<< "$applications_line"

# ========== Generate Certificate Authority (CA) ==========
echo "Generating CA Key and Certificate..."
mkdir -p ./$CERTS_DIR
openssl genrsa -out ./$CERTS_DIR/ca.key 2048
MSYS_NO_PATHCONV=1 openssl req -x509 -new -nodes -key ./$CERTS_DIR/ca.key -sha256 -days 365 \
    -subj "/C=US/ST=California/L=San Francisco/O=My Organization/CN=My CA" \
    -out ./$CERTS_DIR/ca.crt

# ========== Copy Certificate Authority (CA) to Services Directory ==========
echo "Copy CA Key and Certificate to Services..."
for service in "${SERVICES[@]}"; do
    dest="$service/$CERTS_DIR"
    cp ./$CERTS_DIR/ca.key "./$dest/ca.key"
    cp ./$CERTS_DIR/ca.crt "./$dest/ca.crt"
done
rm -rf ./$CERTS_DIR

# ========== Generate Service Certificates and Keys ==========
for service in "${SERVICES[@]}"; do
    dest="$service/$CERTS_DIR"
    cnf="./$dest/$service-san.cnf"

    if [ "$service" == "api-gateway" ]; then
        echo "Generating Client Certificate ($service)..."
    else
        echo "Generating Server Certificate ($service)..."
    fi

    openssl genrsa -out "./$dest/$service.key" 2048
    openssl req -new -key "./$dest/$service.key" -out "./$dest/$service.csr" \
        -config "$cnf"
    openssl x509 -req -in "./$dest/$service.csr" -CA "./$dest/ca.crt" -CAkey "./$dest/ca.key" \
        -CAcreateserial -out "./$dest/$service.crt" -days 365 -sha256 \
        -extfile "$cnf" -extensions v3_req
done

# ========== Verify Certificates ==========
for service in "${SERVICES[@]}"; do
    dest="$service/$CERTS_DIR"

    if [ "$service" == "api-gateway" ]; then
        echo "Verifying Client Certificate ($service)"
    else
        echo "Verifying Server Certificate ($service)"
    fi

    openssl verify -CAfile "./$dest/ca.crt" "./$dest/$service.crt"
done
