#!/usr/bin/env bash
# must be in the spec/docker directory
# must have bolt 3.18+ installed
echo 'Please choose a PE architecture to provision: '
downloads=$(realpath ./)
inventory_dir=$(realpath ./)
inventory_path=${inventory_dir}/inventory.yaml
base_repo=$(realpath ../../)
bolt module install
# bolt will clobber the .modules directory so a new link is required
ln -nfs ../../../ ./.modules/peadm
# The concurrency is set to 2 to keep CPU usage from skyrocketing during Large and XL deployments
select opt in */
do
  dir=$(realpath ${opt})
  name=$(basename $opt)
  cd $dir
  docker-compose up -d --build 
  # nohup /usr/bin/live_audit.sh /root/bolt_scripts /tmp/backup &
  bolt plan run peadm::upgrade --concurrency 2 \
  --inventory $inventory_path \
  --params @${dir}/upgrade_params.json \
  --targets=$name
  break;
done
