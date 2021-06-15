# frozen_string_literal: true

require 'spec_helper'
# TODO: test the error case, however due to an issue with boltspec
# and functions we cannot do this right now.
# https://github.com/puppetlabs/bolt/issues/1688

describe 'peadm::assert_supported_architecture' do
  let(:pre_condition) do
    'type TargetSpec = Variant[String[1], Target, Array[TargetSpec]]'
  end
  let(:primary_host) do
    'puppet-std.puppet.vm'
  end
  let(:replica_host) do
    'pup-replica.puppet.vm'
  end
  let(:primary_postgresql_host) do
    'pup-db.puppet.vm'
  end
  let(:replica_postgresql_host) do
    'pup-db-replica.puppet.vm'
  end
  let(:compiler_hosts) do
    'pup-c1.puppet.vm'
  end

  it {
    is_expected.to run.with_params(primary_host)
                      .and_return('supported' => true,
                                  'disaster-recovery' => false,
                                  'architecture' => 'standard')
  }
  it {
    is_expected.to run.with_params(primary_host, replica_host)
                      .and_return('supported' => true,
                                  'disaster-recovery' => true,
                                  'architecture' => 'standard')
  }

  it do
    is_expected.to run.with_params(primary_host,
                                   replica_host,
                                   nil,
                                   nil,
                                   compiler_hosts)
                      .and_return('supported' => true,
                                  'disaster-recovery' => true,
                                  'architecture' => 'large')
  end

  it do
    is_expected.to run.with_params(primary_host,
                                   nil,
                                   nil,
                                   nil,
                                   compiler_hosts)
                      .and_return('supported' => true,
                                  'disaster-recovery' => false,
                                  'architecture' => 'large')
  end

  it do
    is_expected.to run.with_params(primary_host,
                                   replica_host,
                                   primary_postgresql_host,
                                   replica_postgresql_host,
                                   compiler_hosts)
                      .and_return('supported' => true,
                                  'disaster-recovery' => true,
                                  'architecture' => 'extra-large')
  end

  it do
    is_expected.to run.with_params(primary_host,
                                   nil,
                                   primary_postgresql_host,
                                   nil,
                                   compiler_hosts)
                      .and_return('supported' => true,
                                  'disaster-recovery' => false,
                                  'architecture' => 'extra-large')
  end
end
