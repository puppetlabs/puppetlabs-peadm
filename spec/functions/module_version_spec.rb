# frozen_string_literal: true

require 'spec_helper'

# This function is loaded through Puppet's function loader
# (Puppet::Pops::Loader), not Ruby's `require` -- per
# documentation/test-coverage.md's SimpleCov section, this means
# SimpleCov/Ruby's Coverage module can never attribute this file's
# execution back to lib/puppet/functions/peadm/module_version.rb. This spec
# still adds real regression coverage, it just won't move the SimpleCov
# percentage.
#
# module_version has zero branches and hardcodes 'peadm' as the module it
# looks up (dispatch only declares scope_param -- there is no way for a
# caller to request a different module), so there is exactly one
# meaningful behavioral test: that it reads this module's own real,
# current version rather than something hardcoded/wrong. The version is
# matched by shape (semver-like), not hardcoded, so this spec doesn't go
# stale on every version bump.
describe 'peadm::module_version' do
  it "returns this module's real version string from its own metadata.json" do
    is_expected.to run.and_return(a_string_matching(%r{\A\d+\.\d+\.\d+}))
  end
end
