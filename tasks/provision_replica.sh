#!/bin/bash

USER="${USER:-$(id -un)}"
HOME="${HOME:-$(getent passwd "$USER" | cut -d : -f 6)}"
TOKEN_FILE="${PT_token_file:-"${HOME}/.puppetlabs/token"}"

set -e

env PATH="/opt/puppetlabs/bin:${PATH}" \
    USER="$USER" \
    HOME="$HOME" \
    puppet infrastructure provision replica --token-file "$TOKEN_FILE" \
    "$PT_primary_master_replica"
