#!/bin/bash

set -e

size=$(stat -c%s "$PT_path" 2>/dev/null || echo nil)

# Output a JSON result for ease of Task usage in Puppet Task Plans
if [ "$size" = "nil" ]; then
  echo '{ "size": nil }'
else
  echo '{ "size": "'$size'" }'
fi
