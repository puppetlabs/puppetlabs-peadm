#!/bin/bash

size=$(stat -c%s "$PT_path" 2>/dev/null || echo null)

# Output a JSON result for ease of Task usage in Puppet Task Plans
if [ "$size" = "null" ]; then
  echo '{ "size": null }'
else
  echo '{ "size": "'$size'" }'
fi
