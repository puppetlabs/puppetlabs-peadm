#!/bin/bash

set -e

size=$(stat -c%s "$PT_path" 2>/dev/null)

# Output a JSON result for ease of Task usage in Puppet Task Plans
echo '{ "size": "'$size'" }'
