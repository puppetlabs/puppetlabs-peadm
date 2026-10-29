# frozen_string_literal: true

require 'spec_helper'

# PE-47523: the plans name the PE tarball, and log pe_installer_source, by
# its URL's file name. A URL can carry credentials in its query string (a
# pre-signed URL) or its user info, and none of either may come through. When
# user info holds a raw ? # or /, where it ends can't be told, so the answer
# is undef.
describe 'peadm::url_file_name' do
  [
    ['https://bucket.s3.amazonaws.com/released/puppet-enterprise-2023.8.10-el-8-x86_64.tar.gz' \
     '?X-Amz-Credential=AKIA-canary/20261029/us-east-1/s3/aws4_request&X-Amz-Signature=sig-canary', 'puppet-enterprise-2023.8.10-el-8-x86_64.tar.gz'],
    ['https://artifacts.example.com/pe/puppet-enterprise.tar.gz#fragment-canary', 'puppet-enterprise.tar.gz'],
    ['https://artifacts.example.com/ci/main/puppet-enterprise-2026.0.0-el-8-x86_64.tar', 'puppet-enterprise-2026.0.0-el-8-x86_64.tar'],
    ['https://pm.puppet.com/cgi-bin/download.cgi?dist=el&rel=8&arch=x86_64&ver=2023.8.10', 'download.cgi'],
    ['https://pe-user:password-canary@artifacts.example.com/pe/puppet-enterprise.tar.gz', 'puppet-enterprise.tar.gz'],
    ['https://artifacts.example.com/dl?x=1/pe.tar.gz', 'dl'],
    ['file:///srv/pe/puppet-enterprise.tar.gz', 'puppet-enterprise.tar.gz'],
    ['/tmp/puppet-enterprise.tar.gz', 'puppet-enterprise.tar.gz'],
    ['puppet-enterprise.tar.gz', 'puppet-enterprise.tar.gz'],
  ].each do |url, name|
    it "is #{name} for #{url}" do
      is_expected.to run.with_params(url).and_return(name)
    end
  end

  [
    # A raw ? # or / in the password: where the user info ends can't be told
    'https://pe-user:pass?word-canary@artifacts.example.com/pe/puppet-enterprise.tar.gz',
    'https://pe-user:pass#word-canary@artifacts.example.com/pe/puppet-enterprise.tar.gz',
    'https://pe-user:tok-canary/rest-canary@artifacts.example.com/pe/puppet-enterprise.tar.gz',
    'https://pe-user:tok/rest-canary@artifacts.example.com',
    # An @ after the authority gives undef, even when it is really in the path
    # or query: there is no telling it from user info
    'https://artifacts.example.com/pe@2023.8.10/puppet-enterprise.tar.gz',
    'https://artifacts.example.com/pe/puppet-enterprise.tar.gz?owner=a@b.example.com',
    # No path, and a query: its tail must not become the name, even holding a /
    'https://pe-user:password-canary@artifacts.example.com?id=1-canary',
    'https://bucket.s3.amazonaws.com?X-Amz-Credential=AKIA-canary/20261029/us-east-1/s3/aws4_request&X-Amz-Signature=sig-canary',
    'https://host.example.com?next=/a/b.tar.gz',
    # No file name
    'https://artifacts.example.com/pe/',
    'https://artifacts.example.com',
    'https://artifacts.example.com/?ver=2023.8.10',
  ].each do |url|
    it "is undef for #{url}" do
      is_expected.to run.with_params(url).and_return(nil)
    end
  end
end
