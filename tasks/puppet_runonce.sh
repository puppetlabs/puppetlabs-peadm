#!/bin/bash

unset NOOP_FLAG

if [ "$PT_noop" = "true" ]; then
  NOOP_FLAG="--noop"
fi

/opt/puppetlabs/bin/puppet agent \
  --onetime \
  --verbose \
  --no-daemonize \
  --no-usecacheonfailure \
  --no-splay \
  --no-use_cached_catalog \
  $NOOP_FLAG
