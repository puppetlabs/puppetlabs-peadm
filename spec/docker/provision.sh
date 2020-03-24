#!/usr/bin/env bash
# bundle install
# bundle exec rake spec_prep
# must be in the spec/docker/standard directory
echo 'Please choose a PE architecture to provision: '
downloads=$(realpath ./)
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
  cd $opt
  docker-compose up -d --build
  docker-compose run -v ${downloads}:/downloads -v ${fixtures_path}:/modules -v ${base_repo}:/mods/peadm bolt plan run peadm::provision \
  --concurrency 2 \
  --inventory inventory.yaml \
  --modulepath=/modules:/mods \
  --params @params.json 
  break;
   
done
