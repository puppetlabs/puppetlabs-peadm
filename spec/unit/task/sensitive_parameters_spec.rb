# frozen_string_literal: true

require 'spec_helper'
require 'json'

# PE-47523: Bolt writes every task's arguments to bolt-debug.log at INFO
# ("Running task X with '<args as JSON>'"), the file operators attach to
# support cases. It masks only the parameters whose task metadata sets
# "sensitive": true, so a secret passed through any other parameter lands in
# that file in plaintext. This fails as soon as a task gains a parameter whose
# name looks like a secret without flagging it.
describe 'task metadata' do
  secret_name = %r{password|private_key|license|token|secret|ldap_config}i

  # Parameters whose names match secret_name but don't carry a secret.
  not_secret = {
    'enable_replica.token_file'       => 'path to the token file, not the token',
    'provision_replica.token_file'    => 'path to the token file, not the token',
    'puppet_infra_upgrade.token_file' => 'path to the token file, not the token',
    'validate_rbac_token.token_file'  => 'path to the token file, not the token',
    'rbac_token.token_lifetime'       => 'a duration such as 1y, not a token',
  }

  # Parameters that carry secrets although their names don't say so. The
  # plans write pe.conf (with the console password), the r10k private key,
  # the license and the replica's keys.json files through mkdir_p_file.
  always_sensitive = ['mkdir_p_file.content']

  task_params = Dir[File.expand_path('../../../tasks/*.json', __dir__)].sort.flat_map do |path|
    task = File.basename(path, '.json')
    (JSON.parse(File.read(path))['parameters'] || {}).map { |name, spec| ["#{task}.#{name}", name, spec] }
  end

  checked = task_params.select do |key, name, _spec|
    (name.match?(secret_name) || always_sensitive.include?(key)) && !not_secret.key?(key)
  end

  checked.each do |key, _name, spec|
    it "flags #{key} as sensitive" do
      expect(spec['sensitive']).to be(true)
    end
  end

  # Guards against the glob silently matching nothing, which would leave no
  # examples above and pass.
  it 'checks the parameters that leaked before PE-47523' do
    expect(checked.map(&:first)).to include('rbac_token.password', 'pe_ldap_config.ldap_config', 'mkdir_p_file.content')
  end

  it 'lists only existing task parameters as exceptions' do
    expect(not_secret.keys + always_sensitive - task_params.map(&:first)).to be_empty
  end

  it 'lists only secret-looking names in not_secret' do
    expect(not_secret.keys.reject { |key| key.split('.', 2).last.match?(secret_name) }).to be_empty
  end
end
