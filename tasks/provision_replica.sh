#!/bin/bash

export USER=$(id -un)
export HOME=$(getent passwd "$USER" | cut -d : -f 6)
export PATH="/opt/puppetlabs/bin:${PATH}"

if [ -z "$PT_token_file" -o "$PT_token_file" = "null" ]; then
  export TOKEN_FILE="${HOME}/.puppetlabs/token"
else
  export TOKEN_FILE="$PT_token_file"
fi

puppet infrastructure provision replica "$PT_replica" \
  --yes --token-file "$TOKEN_FILE" \
  --skip-agent-config \
  --topology mono-with-compile \
  --enable
