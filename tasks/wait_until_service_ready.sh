#!/bin/bash

check() {
  if [[ "$PT_service" == 'all' ]]; then
    out=$(curl -fks https://localhost:${PT_port}/status/v1/simple)
  else
    out=$(curl -fks https://localhost:${PT_port}/status/v1/simple/${PT_service})
  fi
}

elapsed=0
until [ $elapsed -gt "$PT_wait_time" ]
do
  check && break
  elapsed=$[$elapsed+3]
  sleep 3
done
