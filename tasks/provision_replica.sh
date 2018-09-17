#!/bin/bash

set -e

env PATH="/opt/puppetlabs/bin:${PATH}" \
    USER="${USER:=$(id -un)}" \
    HOME="${HOME:=$(getent passwd "$USER" | cut -d : -f 6)}" \
    puppet infrastructure provision replica "$PT_primary_master_replica"
