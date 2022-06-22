#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require '/opt/puppetlabs/puppet/cache/lib/pe_install/pe_postgresql_info.rb'

# GetPEAdmConfig task class
class GetPSQLInfo
  def initialize(params); end

  def execute!
    psql_info = PEPostgresqlInfo.new
    data = { 'version' => psql_info.installed_server_version }
    puts data.to_json
  end
end

# Run the task unless an environment flag has been set, signaling not to. The
# environment flag is used to disable auto-execution and enable Ruby unit
# testing of this task.
unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  task = GetPSQLInfo.new(JSON.parse(STDIN.read))
  task.execute!
end
