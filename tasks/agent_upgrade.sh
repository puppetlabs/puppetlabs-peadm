#!/bin/bash

set -e

curl -k "https://${PT_server}:8140/packages/current/upgrade.bash" | bash
