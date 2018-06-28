#!/bin/bash

/opt/puppetlabs/bin/puppet agent \
  --onetime \
  --verbose \
  --no-daemonize \
  --no-usecacheonfailure \
  --no-splay \
  --no-use_cached_catalog
