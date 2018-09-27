#!/bin/bash

USER="${USER:=$(id -un)}"
HOME="${HOME:=$(getent passwd "$USER" | cut -d : -f 6)}"

if [[ "${PT_token_file}x" != 'x' ]] ; then
  TOKEN_FILE="$PT_token_file"
else
  TOKEN_FILE="${HOME}/.puppetlabs/token"
fi

set -e

env PATH="/opt/puppetlabs/bin:${PATH}" \
    USER="$USER" \
    HOME="$HOME" \
    puppet infrastructure enable replica "$PT_primary_master_replica" \
      --skip-agent-config \
      --topology mono-with-compile \
      --yes --token-file "$TOKEN_FILE"
