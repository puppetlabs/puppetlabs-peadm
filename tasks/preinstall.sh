#!/bin/sh

# Setup required packages
packages="curl gnupg"
if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y ${packages} locales

    # Generate en_US.UTF-8 locale for PuppetDB
    if ! locale-gen en_US.UTF-8; then
        echo "Failed to generate locale en_US.UTF-8" >&2
        exit 1
    fi
elif command -v yum >/dev/null 2>&1; then
    yum install -y ${packages} glibc-langpack-en
else
    echo "No supported package manager found (apt-get or yum required)." >&2
    exit 1
fi

exit 0
