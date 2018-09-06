#!/bin/bash
#
# Modified orig source was 'https://github.com/puppetlabs/puppetlabs-bootstrap/blob/master/tasks/linux.sh'
#  Added additional option to manage command_options

validate() {
  if $(echo $1 | grep \' > /dev/null) ; then
    echo "Single-quote is not allowed in arguments" > /dev/stderr
    exit 1
  fi
}

master="$PT_master"
cacert_content="$PT_cacert_content"
certname="$PT_certname"
environment="$PT_environment"
command_options="$PT_command_options"
alt_names="$PT_dns_alt_names"
custom_attribute="$PT_custom_attribute"
extension_request="$PT_extension_request"

validate $certname
validate $environment
validate $alt_names

if [ -n "${certname?}" ] ; then
  certname_arg="agent:certname='${certname}' "
fi
if [ -n "${environment?}" ] ; then
  alt_names_arg="agent:environment='${environment}' "
fi
if [ -n "${alt_names?}" ] ; then
  alt_names_arg="agent:dns_alt_names='${alt_names}' "
fi
if [ -n "${custom_attribute?}" ] ; then
  custom_attributes_arg="custom_attributes:$custom_attribute "
fi
if [ -n "${extension_request?}" ] ; then
  extension_requests_arg="extension_requests:$extension_request "
fi

set -e

flags=$(echo $PT_install_flags | sed -e 's/^\["//' -e 's/\"]$//' -e 's/", *"/ /g')

curl -k "https://${PT_server}:8140/packages/current/install.bash" | bash -s -- $flags
