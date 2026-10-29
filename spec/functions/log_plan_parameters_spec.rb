# frozen_string_literal: true

require 'spec_helper'

# PE-47523: log_plan_parameters prints every key it's given with
# out::message. Today's callers leave secrets out of the hash, but nothing
# stopped one from adding, say, console_password, so values whose keys look
# like secrets print as [redacted]. out::message needs Bolt's executor, which
# BoltSpec::BoltContext#in_bolt_context provides (as in plan_step_spec).
describe 'peadm::log_plan_parameters' do
  include BoltSpec::BoltContext

  around(:each) do |example|
    in_bolt_context do
      example.run
    end
  end

  it 'prints [redacted] for keys that look like secrets and the value for the rest' do
    allow_out_message
    expect_out_message.with_params("Parameter 'primary_host': [primary.example.com]")
    expect_out_message.with_params("Parameter 'console_password': [[redacted]]")
    expect_out_message.with_params("Parameter 'r10k_private_key': [[redacted]]")
    expect_out_message.with_params("Parameter 'license_key_content': [[redacted]]")
    expect_out_message.with_params("Parameter 'ldap_config': [[redacted]]")
    expect_out_message.with_params("Parameter 'Api_TOKEN': [[redacted]]")
    expect_out_message.with_params("Parameter 'client_secret': [[redacted]]")
    expect_out_message.with_params("Parameter 'console_password': [S3cr3t-canary]").not_be_called

    is_expected.to run.with_params({
                                     'primary_host'        => 'primary.example.com',
                                     'console_password'    => 'S3cr3t-canary',
                                     'r10k_private_key'    => '-----BEGIN canary',
                                     'license_key_content' => 'license-canary',
                                     'ldap_config'         => { 'password' => 'ldap-canary' },
                                     'Api_TOKEN'           => 'token-canary',
                                     'client_secret'       => 'secret-canary',
                                   })
    executor.assert_call_expectations
  end
end
