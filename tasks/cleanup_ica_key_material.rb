#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require_relative '../files/ica_task_helper'

# Bolt task: remove the ICA passphrase file from a demoted compiler's
# filesystem. Runs on the compiler. The passphrase file is the only ICA
# secret ever held locally -- the encrypted private key lives in the shared
# database, never on disk. Reads the configured path from ca.conf rather
# than assuming the default, since certificate-authority.ica-passphrase-path
# is operator-configurable. Idempotent: a missing file (already cleaned up,
# or never an ICA compiler) is success, not an error.
class CleanupIcaKeyMaterial
  ICA_PASSPHRASE_PATH_SETTING = 'certificate-authority.ica-passphrase-path'

  def execute!
    path = IcaTaskHelper.get_hocon_value(IcaTaskHelper.ca_conf_path, ICA_PASSPHRASE_PATH_SETTING) ||
           IcaTaskHelper::DEFAULT_ICA_PASSPHRASE_PATH

    removed = delete_if_exists(path)

    STDOUT.puts({ 'path' => path, 'removed' => removed }.to_json)
    exit 0
  rescue StandardError => e
    STDOUT.puts({ '_error' => { 'msg' => e.message, 'kind' => 'peadm/cleanup_ica_key_material_failed' } }.to_json)
    exit 1
  end

  private

  # Deletes unconditionally rather than checking existence first, so a
  # symlink swapped in between a check and a delete can't redirect this at
  # an arbitrary file the puppetserver process user can write to.
  def delete_if_exists(path)
    File.delete(path)
    true
  rescue Errno::ENOENT
    false
  end
end

unless ENV['RSPEC_UNIT_TEST_MODE']
  CleanupIcaKeyMaterial.new.execute!
end
