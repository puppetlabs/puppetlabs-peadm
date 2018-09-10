#!/bin/bash

function main()
{
  while getopts ":v" opt; do
    case $opt in
      v)
        g_verbose='true'
        ;;
    esac
  done

  shift $((OPTIND-1))

  case "$1" in
    deploy)
      action=deploy
      ;;
    commit)
      action=commit
      ;;
    r10k)
      action=cm_r10k
      ;;
    flush-environment-cache)
      action=flush_environment_cache
      ;;
    file-sync)
      action=file_sync
      ;;
    *)
      cat <<-EOF
				
				Usage: $(basename $0) [-v] <subcommand>
				
				Available subcommands:
				
				  deploy <environment>
				    Roughly equivalent to "puppet code deploy <env>". Invokes r10k to
				    deploy the environment to the staging-dir, invokes file-sync to
				    commit and sync the files, then flushes puppetserver's environment
				    cache.
				
				  commit
				    Commits all files in code-staging and deploys them.
				
				  r10k <arguments>
				    Invokes r10k in the context of code manager. Normal r10k arguments
				    should be provided.
				
				  file-sync <subcommand>
				    Run the file-sync subcommand with no other options for further
				    usage instructions.
				
				  flush-environment-cache
				    Flush the puppetserver environment cache, causing it to re-read code
				    from the code-dir.
				
				EOF
      exit 1
      ;;
  esac

  g_certname=$(/opt/puppetlabs/bin/puppet config print certname --section agent)

  shift
  $action "$@"
}

function deploy()
{
  [ "$#" = 1 ] || { echo "specify an environment to deploy"; exit 1; }
  cm_r10k deploy environment "$1" && commit
}

function commit()
{
  # Perform two calls to file-sync. First, commit the code from code-staging.
  # Second, force a sync/deploy to the code directory. The second step is
  # performed explicitly so that we are guaranteed the deploy is finished
  # before we take any action that depends on that task being done.
  fs_commit
  fs_force_sync
}

function cm_r10k()
{
  args=$@
  su - pe-puppet -s /bin/bash -c "/opt/puppetlabs/bin/r10k ${args} \
    -c /opt/puppetlabs/server/data/code-manager/r10k.yaml"
}

function file_sync()
{
  case "$1" in
    commit)
      fs_commit
      ;;
    force-sync)
      fs_force_sync
      ;;
    *)
      cat <<-EOF
				
				Usage: $(basename $0) [-v] file-sync <subcommand>
				
				Available subcommands:
				
				  commit
				    Calls the file-sync storage API to read and commit all code in
				    the staging-dir. Does not force the client to sync or flush
				    the puppetserver environment cache.
				
				  force-sync
				    Calls the file-sync client API to force the code-dir to be updated
				    with the latest available code from the storage service. Does not 
				    flush the puppetserver environment cache.
				
				EOF
      exit 1
      ;;
  esac

}

function fs_commit()
{
  curl_wrapper -ks --request POST --header "Content-Type: application/json" \
    --cert "/etc/puppetlabs/puppet/ssl/certs/${g_certname}.pem" \
    --key "/etc/puppetlabs/puppet/ssl/private_keys/${g_certname}.pem" \
    --cacert "/etc/puppetlabs/puppet/ssl/certs/ca.pem" \
    --data '{"commit-all": true}' \
    'https://localhost:8140/file-sync/v1/commit'
}

function fs_force_sync()
{
  curl_wrapper -ks --request POST --header "Content-Type: application/json" \
    --cert "/etc/puppetlabs/puppet/ssl/certs/${g_certname}.pem" \
    --key "/etc/puppetlabs/puppet/ssl/private_keys/${g_certname}.pem" \
    --cacert "/etc/puppetlabs/puppet/ssl/certs/ca.pem" \
    'https://localhost:8140/file-sync/v1/force-sync'
}

function flush_environment_cache()
{
  curl_wrapper -ks --request DELETE --header "Content-Type: application/json" \
    --cert "/etc/puppetlabs/puppet/ssl/certs/${g_certname}.pem" \
    --key "/etc/puppetlabs/puppet/ssl/private_keys/${g_certname}.pem" \
    --cacert "/etc/puppetlabs/puppet/ssl/certs/ca.pem" \
    'https://localhost:8140/puppet-admin-api/v1/environment-cache'
}

function curl_wrapper()
{
  [ "$g_verbose" = 'true' ] && echo "command: curl $@"
  output=$(curl "$@")
  exitcode=$?
  if [ "$g_verbose" = 'true' ]; then
    echo "output json:"
    echo "$output" | python -m json.tool || echo "raw output: $output"
    echo "exitcode: $exitcode"
    echo
  fi
}

main $PT_action
