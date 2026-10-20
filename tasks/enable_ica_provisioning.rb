#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'puppet'
require_relative '../files/ica_task_helper'

# Bolt task: stage one of promotion. Pins this compiler into the
# PE Intermediate CA classifier group so that, on its next Puppet run,
# profile::compiler_ica_ca writes the ca.conf settings the ICA provisioning
# subcommand reads. The compiler stays a CA proxy: nothing here sets the flags
# that bind IntermediateCAService, which is prepare_ica_promotion's job once the
# request is approved. Running Puppet afterwards is the calling plan's job.
class EnableIcaProvisioning
  def initialize(params)
    @primary_host = params.fetch('primary_host')
  end

  def execute!
    classifier_https = IcaTaskHelper.primary_https_client(@primary_host, IcaTaskHelper::CLASSIFIER_PORT)
    IcaTaskHelper.pin_to_ica_parent_group!(classifier_https, Puppet.settings[:certname])

    STDOUT.puts({ 'status' => 'pinned' }.to_json)
    exit 0
  rescue StandardError => e
    warn "#{e.class}: #{e.message}"
    warn e.backtrace.first(10).join("\n") if e.backtrace
    IcaTaskHelper.emit_error!(e.message, 'peadm/enable_ica_provisioning_failed')
    exit 1
  end
end

unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  EnableIcaProvisioning.new(JSON.parse(STDIN.read)).execute!
end
