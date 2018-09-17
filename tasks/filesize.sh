#!/bin/bash

set -e

echo $(stat -c%s "$PT_path" 2>/dev/null)
