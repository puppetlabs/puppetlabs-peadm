#!/bin/bash

urisize=$(curl -s -L --head "$PT_source" | sed -n 's/Content-Length: \([0-9]\+\)/\1/p' | tr -d '\012\015')
filesize=$(stat -c%s "$PT_path" 2>/dev/null)

# Assume that if the file exists and is the same size, we don't have to
# re-download.
if [[ ! -z "$urisize" && ! -z "$filesize" && "$filesize" -eq "$urisize" ]]; then
  exit 0
else
  curl -L -o "$PT_path" "$PT_source"
fi
