#!/bin/bash

download() {
  curl -o "${PT_filename}" "https://s3.amazonaws.com/pe-builds/released/${PT_version}/puppet-enterprise-${PT_version}-el-7-x86_64.tar.gz"
}

# Make this assume that if the file exists and is of a certain minimum size
# it's probably good enough to use and don't have to re-download.
acceptsize=400000000
if [ ! -e "${PT_filename}" ]; then
  download
elif [ ! $(stat -c%s "$PT_filename") -gt "$acceptsize" ]; then
  download
else
  exit 0
fi
