#!/bin/bash

USER="${USER:-$(id -un)}"
HOME="${HOME:-$(getent passwd "$USER" | cut -d : -f 6)}"

if [ -z "$PT_token_file" -o "$PT_token_file" = "null" ]; then
  TOKEN_FILE="${HOME}/.puppetlabs/token"
else
  TOKEN_FILE="$PT_token_file"
fi

set -e

env PATH="/opt/puppetlabs/bin:${PATH}" \
    USER="$USER" \
    HOME="$HOME" \
    puppet infrastructure provision replica --token-file "$TOKEN_FILE" \
    "$PT_master_replica"
