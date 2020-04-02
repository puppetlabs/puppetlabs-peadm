#!/bin/bash

# This task exists as a convenience for users who need predictable sudo
# commands without variance to write into their sudoers rules. The only real
# variable in commands used by peadm is the filename of the PE installer
# tarball. This task can be used in a pre-plan to homogenize calls to sudo.
# Rather than literally calling "mv" with a variable filename, the mv.sh task
# can be called. Inputs come as environment variables so the call doesn't
# change.

mv "$PT_source" "$PT_target"
