#!/bin/bash

[ "$PT_noop" = "true" ] && NOOP_FLAG="--noop" || unset NOOP_FLAG

# Wait for up to five minutes for an in-progress Puppet agent run to complete
# TODO: right now the check is just for lock file existence. Improve the check
#       to account for situations where the lockfile is stale.
echo -n "Check for and wait up to 5 minutes for in-progress run to complete: "
lockfile=$(/opt/puppetlabs/bin/puppet config print agent_catalog_run_lockfile)
n=0
until [ $n -ge 300 ]
do
  [ ! -e "$lockfile" ] && break
  echo -n .
  n=$[$n+1]
  sleep 1
done
echo

/opt/puppetlabs/bin/puppet agent \
  --onetime \
  --verbose \
  --no-daemonize \
  --no-usecacheonfailure \
  --no-splay \
  --no-use_cached_catalog \
  $NOOP_FLAG
