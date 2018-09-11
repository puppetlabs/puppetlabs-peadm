#!/bin/bash

set -e

env PATH=/opt/puppetlabs/bin:$PATH puppet infrastructure enable replica $PT_primary_master_replica \
  --skip-agent-config \
  --topology mono-with-compile \
  --yes
