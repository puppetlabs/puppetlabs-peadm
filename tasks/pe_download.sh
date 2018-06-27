#!/bin/bash

uri="https://s3.amazonaws.com/pe-builds/released/${PT_version}/puppet-enterprise-${PT_version}-el-7-x86_64.tar.gz"
urisize=$(curl -s --head $uri | sed -n -e 's/^M//' -e 's/Content-Length: \([0-9]\+\)/\1/p')
filesize=$(stat -c%s "$PT_filename" 2>/dev/null)

# Assume that if the file exists and is of a certain minimum size
# it's probably good enough to use and don't have to re-download.
if [ "$filesize" -ne "$urisize" ]; then
  curl -o "$PT_filename" "$uri"
else
  exit 0
fi
