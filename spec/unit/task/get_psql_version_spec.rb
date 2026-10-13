require 'spec_helper'

# tasks/get_psql_version.rb requires a sibling Bolt module file
# (ruby_task_helper/files/task_helper.rb) via a path that only resolves when
# installed under a real Puppet modulepath (peadm/tasks/.. ->
# modules/ruby_task_helper/..), and a PE-only native library
# (pe_install/pe_postgresql_info.rb) via an absolute path that only exists on
# a real PE node. Neither resolves in this checkout. Pre-register both exact
# paths in $LOADED_FEATURES so Ruby's require/require_relative treat them as
# already loaded and skip them, then provide minimal stand-ins for the two
# classes the task needs so the real task file can still be exercised.
#
# This runs at file-load time (not inside a before/after hook), so it's
# global, process-wide, and never undone -- a deliberate, scoped tradeoff.
# It's safe today because no other file in this repo requires
# ruby_task_helper/task_helper.rb or defines TaskHelper/PEPostgresqlInfo
# (confirmed via grep); if that ever changes, this stand-in would silently
# shadow the real class for the rest of the suite's process.
task_file = File.expand_path('../../../tasks/get_psql_version.rb', __dir__)

task_helper_path = File.expand_path('../../ruby_task_helper/files/task_helper.rb', File.dirname(task_file))
$LOADED_FEATURES << task_helper_path unless $LOADED_FEATURES.include?(task_helper_path)

pe_postgresql_info_path = '/opt/puppetlabs/puppet/cache/lib/pe_install/pe_postgresql_info.rb'
$LOADED_FEATURES << pe_postgresql_info_path unless $LOADED_FEATURES.include?(pe_postgresql_info_path)

unless defined?(TaskHelper)
  class TaskHelper
  end
end

unless defined?(PEPostgresqlInfo)
  class PEPostgresqlInfo
    def installed_server_version; end
  end
end

require_relative '../../../tasks/get_psql_version'

# This spec file is intentionally named after the task file (get_psql_version.rb),
# not RuboCop's snake_case derivation of the class name (GetPSQLInfo), for discoverability.
# rubocop:disable RSpec/SpecFilePathFormat
describe GetPSQLInfo do
  subject(:task) { described_class.new }

  let(:psql_info_dbl) { instance_double(PEPostgresqlInfo) }

  before(:each) do
    allow(PEPostgresqlInfo).to receive(:new).and_return(psql_info_dbl)
  end

  # Catches a mutation that hardcodes a version string, swaps in a
  # different method call, or returns the raw string instead of the
  # {'version' => ...} shape the task's JSON output contract requires.
  it "returns the installed server version under the 'version' key" do
    allow(psql_info_dbl).to receive(:installed_server_version).and_return('15')

    expect(task.task).to eq('version' => '15')
  end

  # Catches a mutation that reuses a stale/memoized version string instead
  # of querying the installed version fresh each call. Calls task.task
  # twice against a stub that returns a different value each time, so a
  # cached/hardcoded value from the first call would fail the second.
  it 'queries installed_server_version afresh on each call, not a cached/memoized value' do
    allow(psql_info_dbl).to receive(:installed_server_version).and_return('15', '16')

    expect(task.task).to eq('version' => '15')
    expect(task.task).to eq('version' => '16')
  end

  # Catches a mutation that changes the method signature to require
  # specific task parameters instead of accepting and discarding any.
  it 'accepts and ignores arbitrary task parameters' do
    allow(psql_info_dbl).to receive(:installed_server_version).and_return('15')

    expect { task.task(unused: 'param') }.not_to raise_error
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
