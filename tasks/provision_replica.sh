#!/bin/bash

env PATH=/opt/puppetlabs/bin:$PATH puppet infrastructure provision replica $PT_primary_master_replica

EXIT=$?

if [[ $EXIT == '1' ]]; then
  echo 'Provision exitted with a code 1, NOT worth stopping for. Continuing.'
  exit 0
fi

exit $EXIT
