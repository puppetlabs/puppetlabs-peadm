# frozen_string_literal: true

require 'spec_helper'

# PE-47523: the plans name the PE tarball, and log pe_installer_source, by
# its URL's file name. A URL can carry credentials in its query string (a
# pre-signed URL) or its user info, and none of either may come through,
# even when a password holds a raw ? # or /.
describe 'peadm::url_file_name' do
  [
    ['https://bucket.s3.amazonaws.com/released/puppet-enterprise-2023.8.10-el-8-x86_64.tar.gz' \
     '?X-Amz-Credential=AKIA-canary/20261029/us-east-1/s3/aws4_request&X-Amz-Signature=sig-canary', 'puppet-enterprise-2023.8.10-el-8-x86_64.tar.gz'],
    ['https://artifacts.example.com/pe/puppet-enterprise.tar.gz#fragment-canary', 'puppet-enterprise.tar.gz'],
    ['https://pm.puppet.com/cgi-bin/download.cgi?dist=el&rel=8&arch=x86_64&ver=2023.8.10', 'download.cgi'],
    ['https://pe-user:password-canary@artifacts.example.com/pe/puppet-enterprise.tar.gz', 'puppet-enterprise.tar.gz'],
    ['https://pe-user:pass?word-canary@artifacts.example.com/pe/puppet-enterprise.tar.gz', 'puppet-enterprise.tar.gz'],
    ['https://pe-user:pass#word-canary@artifacts.example.com/pe/puppet-enterprise.tar.gz', 'puppet-enterprise.tar.gz'],
    ['https://pe-user:tok-canary/rest-canary@artifacts.example.com/pe/puppet-enterprise.tar.gz', 'puppet-enterprise.tar.gz'],
    ['/tmp/puppet-enterprise.tar.gz', 'puppet-enterprise.tar.gz'],
  ].each do |url, name|
    it "is #{name} for #{url}" do
      is_expected.to run.with_params(url).and_return(name)
    end
  end

  [
    'https://pe-user:password-canary@artifacts.example.com?id=1-canary',
    # A raw / in the password, and no path: what's left of the password
    # would look like the file name.
    'https://pe-user:tok/rest-canary@artifacts.example.com',
    'https://artifacts.example.com/pe/',
    'https://artifacts.example.com',
  ].each do |url|
    it "is undef for #{url}" do
      is_expected.to run.with_params(url).and_return(nil)
    end
  end
end
