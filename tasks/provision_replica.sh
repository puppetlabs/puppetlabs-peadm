#!/bin/bash

# Try and ensure locale is correctly configured
[ -z "${LANG}" ] && export LANG=$(localectl status | sed -n 's/.* LANG=\(.*\)/\1/p')

# declare task parameters for linting
declare PT_token_file
declare PT_legacy
declare PT_replica
declare PT_action

export USER=$(id -un)
export HOME=$(getent passwd "$USER" | cut -d : -f 6)
export PATH="/opt/puppetlabs/bin:${PATH}"

if [ -z "$PT_token_file" -o "$PT_token_file" = "null" ]; then
  export TOKEN_FILE="${HOME}/.puppetlabs/token"
else
  export TOKEN_FILE="$PT_token_file"
fi


set -e

if [ -z "$PT_action" -o "$PT_action" = "null" ]; then
  PT_action="both"
fi

if [ "$PT_legacy" = "false" ]; then
  echo "(legacy=false) query active nodes before provision replica"
  puppet query '["from","resources",["extract",["certname"],["and",["=","type","Class"],["=","title","Puppet_enterprise::Profile::Master"]]]]'

  case "$PT_action" in
    provision)
      # Provision only, without the trailing --enable. PE core's --enable
      # path runs its own replica service-health check with a short, fixed
      # wait that is sometimes too short in CI; callers that split
      # provision/enable are expected to confirm service health themselves
      # (e.g. peadm::wait_until_service_ready) before calling this task
      # again with action=enable.
      puppet infrastructure provision replica "$PT_replica" \
        --color false \
        --yes --token-file "$TOKEN_FILE" \
        --skip-agent-config \
        --topology mono-with-compile
      ;;
    enable)
      puppet infrastructure enable replica "$PT_replica" \
        --color false \
        --yes --token-file "$TOKEN_FILE" \
        --skip-agent-config \
        --topology mono-with-compile
      ;;
    both|*)
      puppet infrastructure provision replica "$PT_replica" \
        --color false \
        --yes --token-file "$TOKEN_FILE" \
        --skip-agent-config \
        --topology mono-with-compile \
        --enable
      ;;
  esac

elif [ "$PT_legacy" = "true" ]; then
  case "$PT_action" in
    provision)
      echo "(legacy=true) query active nodes before provision replica"
      puppet query '["from","resources",["extract",["certname"],["and",["=","type","Class"],["=","title","Puppet_enterprise::Profile::Master"]]]]'

      puppet infrastructure provision replica "$PT_replica" \
        --color false \
        --token-file "$TOKEN_FILE"
      ;;
    enable)
      echo "(legacy=true) query active nodes before enable replica"
      puppet query '["from","resources",["extract",["certname"],["and",["=","type","Class"],["=","title","Puppet_enterprise::Profile::Master"]]]]'
      puppet infrastructure enable replica "$PT_replica" \
        --color false \
        --yes --token-file "$TOKEN_FILE" \
        --skip-agent-config \
        --topology mono-with-compile
      ;;
    both|*)
      echo "(legacy=true) query active nodes before provision replica"
      puppet query '["from","resources",["extract",["certname"],["and",["=","type","Class"],["=","title","Puppet_enterprise::Profile::Master"]]]]'

      puppet infrastructure provision replica "$PT_replica" \
        --color false \
        --token-file "$TOKEN_FILE"

      echo "(legacy=true) query active nodes before enable replica"
      puppet query '["from","resources",["extract",["certname"],["and",["=","type","Class"],["=","title","Puppet_enterprise::Profile::Master"]]]]'
      puppet infrastructure enable replica "$PT_replica" \
        --color false \
        --yes --token-file "$TOKEN_FILE" \
        --skip-agent-config \
        --topology mono-with-compile
      ;;
  esac

else
  exit 1
fi
