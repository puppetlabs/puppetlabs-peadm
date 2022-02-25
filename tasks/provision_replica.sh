#!/bin/bash

# Try and ensure locale is correctly configured
[ -z "${LANG}" ] && export LANG=$(localectl status | sed -n 's/.* LANG=\(.*\)/\1/p')

export USER=$(id -un)
export HOME=$(getent passwd "$USER" | cut -d : -f 6)
export PATH="/opt/puppetlabs/bin:${PATH}"

if [ -z "$PT_token_file" -o "$PT_token_file" = "null" ]; then
  export TOKEN_FILE="${HOME}/.puppetlabs/token"
else
  export TOKEN_FILE="$PT_token_file"
fi


set -e

if [ "$PT_legacy" = "false" ]; then
  puppet infrastructure provision replica "$PT_replica" \
    --color false \
    --yes --token-file "$TOKEN_FILE" \
    --skip-agent-config \
    --topology mono-with-compile \
    --enable

elif [ "$PT_legacy" = "true" ]; then
  puppet infrastructure provision replica "$PT_replica" \
    --color false \
    --token-file "$TOKEN_FILE"

  puppet infrastructure enable replica "$PT_replica" \
    --color false \
    --yes --token-file "$TOKEN_FILE" \
    --skip-agent-config \
    --topology mono-with-compile

else
  exit 1
fi
