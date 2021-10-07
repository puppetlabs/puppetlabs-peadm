#!/usr/bin/env bash
# Purpose: Create container agents for docker examples
PE_SERVER=$1
MAX_AGENTS="${2:-5}"
if [[ -z $PE_SERVER ]]; then
  echo "No pe server provided, please provide the fqdn of your primary servername"
  echo "Example usage: $0 pe-std.puppet.vm [num agent containers]"
	echo "The default number of agent containers is 5"
	exit 1
fi
SRV_CMD="echo ${PE_SERVER} | cut -d. -f1"
BASE_NAME=$(eval $SRV_CMD)
DOCKER_NETWORK=$(docker inspect ${PE_SERVER} -f "{{json .HostConfig.NetworkMode }}" | sed -e 's/^"//' -e 's/"$//')
if [[ -z $DOCKER_NETWORK ]]; then
  echo "docker network not found for ${PE_SERVER}, exiting"
  exit 1
fi
# start loop here
for (( i=1; i<=$MAX_AGENTS; i++ ))
do  
	# need a way better way come up with a unique hostname
	AGENT_HOSTNAME="${BASE_NAME}-agent-${i}.puppet.vm"
	#--name $AGENT_HOSTNAME --hostname=$AGENT_HOSTNAME could be usedbut we will get duplicate certs without cleaning on ca
	INSTALL_CMD="curl -k https://${PE_SERVER}:8140/packages/current/install.bash | bash"
	RUN_CMD="docker run -d -t --network=${DOCKER_NETWORK} --privileged --label=\"${BASE_NAME}-agent\" --label=\"docker-example-agent\" -v /sys/fs/cgroup:/sys/fs/cgroup:ro pe-base"
	echo RUN_CMD
	CONTAINER=$(eval $RUN_CMD)
	CONTAINER=${CONTAINER:0:12}
	if [[ -z $CONTAINER ]]; then
	  echo "Container was not started for some reason"
	  exit 1
	fi
	SETUP="docker exec -ti $CONTAINER sh -c \"${INSTALL_CMD} && puppet agent -t\""
	eval $SETUP
	CHOST=$(docker exec $CONTAINER /opt/puppetlabs/bin/puppet config print certname)
	# if user manually signs certs, we need to fail gracefully 
	docker exec -ti $PE_SERVER sh -c "/opt/puppetlabs/bin/puppetserver ca sign --certname ${CHOST}"
	docker exec -ti $CONTAINER sh -c "puppet agent -t"
done
