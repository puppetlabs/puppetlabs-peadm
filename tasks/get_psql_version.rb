#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require_relative '../../ruby_task_helper/files/task_helper.rb'
require '/opt/puppetlabs/puppet/cache/lib/pe_install/pe_postgresql_info.rb'

# Task which fetches the installed PSQL server major version
class GetPSQLInfo < TaskHelper
  def task(**_kwargs)
    psql_info = PEPostgresqlInfo.new
    { 'version' => psql_info.installed_server_version }
  end
end

GetPSQLInfo.run if $PROGRAM_NAME == __FILE__
