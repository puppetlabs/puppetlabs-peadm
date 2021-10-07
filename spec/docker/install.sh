#!/usr/bin/env bash
# must be in the spec/docker directory
# must have bolt 3.18+ installed
downloads=$(realpath ./)
inventory_dir=$(realpath ./)
inventory_path=${inventory_dir}/inventory.yaml
base_repo=$(realpath ../../)
spec_path=$(realpath ../)
bolt module install
ln -nfs ../../../ ./.modules/peadm
# The concurrency is set to 2 to keep CPU usage from skyrocketing during Large and XL deployments
echo 'Please choose a PE architecture to provision: '

select opt in */
do
  dir=$(realpath ${opt})
  name=$(basename $opt)
  cd $dir
  docker-compose up -d --build 
  bolt plan run peadm::install --concurrency 2 \
  --inventory $inventory_path \
  --params @${dir}/params.json \
  --targets=$name
  break;
done
# --modulepath=./modules \
