#!/bin/bash

case $(uname) in
Darwin)
  options="-f%z"
  ;;
*)
  options="-c%s"
  ;;
esac

size=$(stat "$options" "$PT_path" 2>/dev/null || echo null)

# Output a JSON result for ease of Task usage in Puppet Task Plans
if [ "$size" = "null" ]; then
  echo '{ "size": null }'
else
  echo '{ "size": "'$size'" }'
fi
