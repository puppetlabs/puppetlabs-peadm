#!/usr/bin/env bash
# bundle install or pdk bundle install
# bundle exec rake spec_prep or pdk bundle exec rake spec_prep
# must be in the spec/docker directory
echo 'Please choose a PE architecture to provision: '
downloads=$(realpath ./)
inventory_dir=$(realpath ./)
inventory_path=${inventory_dir}/inventory.yaml
base_repo=$(realpath ../../)
spec_path=$(realpath ../)
fixtures_path=$spec_path/fixtures/modules
num=$(ls ${fixtures_path} | wc -l)
if [[ ! "$num" -gt "8" ]]; then
  echo "No fixtures, please run bundle exec rake spec_prep or pdk bundle exec rake spec_prep"
  exit 1
fi
# The concurrency is set to 2 to keep CPU usage from skyrocketing during Large and XL deployments
select opt in */
do
  dir=$(realpath ${opt})
  name=$(basename $opt)
  cd $dir
  docker-compose up -d --build 
  # nohup /usr/bin/live_audit.sh /root/bolt_scripts /tmp/backup &
  pdk bundle exec bolt plan run peadm::upgrade --concurrency 2 \
  --inventory $inventory_path \
  --modulepath=$fixtures_path \
  --params @${dir}/upgrade_params.json \
  --targets=$name
  break;
done
