# frozen_string_literal: true

require 'spec_helper'

# PE-47523: log_plan_parameters prints every key it's given with
# out::message. Values whose keys look like secrets print as [redacted]. This
# is a backstop: it goes by top-level key name only, so it can't catch a
# secret stored under an innocuous key, or nested inside another value.
# out::message needs Bolt's executor, which BoltSpec::BoltContext provides
# (as in plan_step_spec); every message is captured so a leak in any format
# fails.
describe 'peadm::log_plan_parameters' do
  include BoltSpec::BoltContext

  around(:each) do |example|
    in_bolt_context do
      example.run
    end
  end

  let(:messages) { [] }

  before(:each) do
    allow_out_message
    allow(executor).to receive(:publish_event).and_wrap_original do |original, event|
      messages << event[:message] if event[:type] == :message
      original.call(event)
    end
  end

  it 'prints [redacted] for keys that look like secrets and the value for the rest' do
    secrets = {
      'console_password'    => 'password-canary',
      'Api_TOKEN'           => 'token-canary',
      'r10k_private_key'    => 'key-canary',
      'license_key_content' => 'license-canary',
      'client_secret'       => 'secret-canary',
      'ldap_config'         => { 'password' => 'ldap-canary' },
      'db_passwd'           => 'passwd-canary',
      'ssh_passphrase'      => 'passphrase-canary',
      'credentials'         => 'credential-canary',
      'service_api_key'     => 'api-key-canary',
    }

    is_expected.to run.with_params({ 'primary_host' => 'primary.example.com', 'replica_host' => nil }.merge(secrets))

    expect(messages).to include("Parameter 'primary_host': [primary.example.com]", "Parameter 'replica_host': []")
    secrets.each_key { |key| expect(messages).to include("Parameter '#{key}': [[redacted]]") }
    expect(messages.grep(%r{canary})).to be_empty
  end
end
