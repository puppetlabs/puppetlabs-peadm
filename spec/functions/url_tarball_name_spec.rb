# frozen_string_literal: true

require 'spec_helper'

# The plans use this for the PE tarball's name and for what they log of
# pe_installer_source: only a name ending in .tar or .tar.gz, never another
# last path segment, which can be a token.
describe 'peadm::url_tarball_name' do
  [
    ['https://artifacts.example.com/pe/puppet-enterprise-2023.8.10-el-8-x86_64.tar.gz?sig=sig-canary', 'puppet-enterprise-2023.8.10-el-8-x86_64.tar.gz'],
    ['https://artifacts.example.com/ci/puppet-enterprise-2026.0.0-el-8-x86_64.tar', 'puppet-enterprise-2026.0.0-el-8-x86_64.tar'],
    ['https://artifacts.example.com/pe/pe-latest.tar.gz', 'pe-latest.tar.gz'],
    ['https://artifacts.example.com/ci/puppet-enterprise-2025.4.0+build5-el-8-x86_64.tar', 'puppet-enterprise-2025.4.0+build5-el-8-x86_64.tar'],
  ].each do |url, name|
    it "is #{name} for #{url}" do
      is_expected.to run.with_params(url).and_return(name)
    end
  end

  [
    'https://pm.puppet.com/cgi-bin/download.cgi?dist=el&ver=2023.8.10',
    'https://artifacts.example.com/dl/token-canary',
    'https://artifacts.example.com/pe/x.tar.gz.asc',
    'https://artifacts.example.com/pe/..tar',
    'https://artifacts.example.com/pe/-rf.tar',
    "https://artifacts.example.com/pe/it's.tar.gz",
    'https://artifacts.example.com/pe/a%20b.tar.gz',
    'https://artifacts.example.com/pe/',
    'https://pe-user:pass#word-canary@artifacts.example.com/pe/puppet-enterprise.tar.gz',
  ].each do |url|
    it "is undef for #{url}" do
      is_expected.to run.with_params(url).and_return(nil)
    end
  end
end
