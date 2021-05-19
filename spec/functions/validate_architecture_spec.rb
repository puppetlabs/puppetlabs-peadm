# frozen_string_literal: true

require 'spec_helper'
# TODO: test the error case, however due to an issue with boltspec
# and functions we cannot do this right now.
# https://github.com/puppetlabs/bolt/issues/1688

describe 'peadm::validate_architecture' do
  let(:pre_condition) do
    'type TargetSpec = Variant[String[1], Target, Array[TargetSpec]]'
  end
  let(:primary_host) do
    'puppet-std.puppet.vm'
  end
  let(:primary_replica_host) do
    'pup-replica.puppet.vm'
  end
  let(:puppetdb_database_host) do
    'pup-db.puppet.vm'
  end
  let(:puppetdb_database_replica_host) do
    'pup-db-replica.puppet.vm'
  end
  let(:compiler_hosts) do
    'pup-c1.puppet.vm'
  end

  it {
    is_expected.to run.with_params(primary_host)
                      .and_return('high-availability' => false, 'architecture' => 'standard')
  }
  it {
    is_expected.to run.with_params(primary_host, primary_replica_host)
                      .and_return('high-availability' => true, 'architecture' => 'standard')
  }

  it do
    is_expected.to run.with_params(
      primary_host,
      primary_replica_host,
      nil,
      nil,
      compiler_hosts,
    )
                      .and_return('high-availability' => true, 'architecture' => 'large')
  end

  it do
    is_expected.to run.with_params(
      primary_host,
      nil,
      nil,
      nil,
      compiler_hosts,
    )
                      .and_return('high-availability' => false, 'architecture' => 'large')
  end

  it do
    is_expected.to run.with_params(
      primary_host,
      primary_replica_host,
      puppetdb_database_host,
      puppetdb_database_replica_host,
      compiler_hosts,
    )
                      .and_return('high-availability' => true, 'architecture' => 'extra-large')
  end

  it do
    is_expected.to run.with_params(
      primary_host,
      nil,
      puppetdb_database_host,
      nil,
      compiler_hosts,
    )
                      .and_return('high-availability' => false, 'architecture' => 'extra-large')
  end
end
