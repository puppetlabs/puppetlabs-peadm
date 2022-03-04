#!/bin/bash

check() {
  if [[ "$PT_service" == 'all' ]]; then
    out=$(curl -fks https://localhost:${PT_port}/status/v1/simple)
  else
    out=$(curl -fks https://localhost:${PT_port}/status/v1/simple/${PT_service})
  fi
}

n=0
until [ $n -ge 20 ]
do
  check && break
  n=$[$n+1]
  sleep 3
done
