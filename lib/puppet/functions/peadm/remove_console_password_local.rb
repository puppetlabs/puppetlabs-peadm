# frozen_string_literal: true

require_relative '../../../../tasks/remove_console_password'

# Runs inside Bolt, so the file is edited locally without transferring secrets.
Puppet::Functions.create_function(:'peadm::remove_console_password_local') do
  dispatch :remove_console_password_local do
    param 'String[1]', :params_file
    return_type 'Hash'
  end

  def remove_console_password_local(params_file)
    RemoveConsolePassword.clean(params_file, ['console_password', 'console_admin_password'])
  rescue StandardError
    raise Puppet::Error, 'Could not clean the local params file; expected an accessible regular JSON object file with one hard link.'
  end
end
