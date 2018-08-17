#!/bin/bash

set -e

env PATH=/opt/puppetlabs/bin:$PATH puppet infrastructure provision replica $PT_primary_master_replica

