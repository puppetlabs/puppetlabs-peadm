# frozen_string_literal: true

require 'spec_helper'
require 'json'

# PE-47523: Bolt writes every task's arguments to bolt-debug.log at INFO
# ("Running task X with '<args as JSON>'"), the file operators attach to
# support cases. It masks only the parameters whose task metadata sets
# "sensitive": true, so a secret passed through any other parameter lands in
# that file in plaintext. These examples fail as soon as a task gains a
# parameter whose name looks like a secret without flagging it, or takes a
# flagged parameter as environment input. (Task results are logged too:
# peadm::read_sensitive_file covers the reads that return secrets.)
describe 'task metadata' do
  # Keep in sync with functions/log_plan_parameters.pp; the last example
  # checks that.
  secret_name = %r{password|passwd|passphrase|private_key|license|token|secret|credential|api_key|ldap_config}i

  # Parameters whose names match secret_name but don't carry a secret.
  not_secret = {
    'enable_replica.token_file'       => 'path to the token file, not the token',
    'provision_replica.token_file'    => 'path to the token file, not the token',
    'puppet_infra_upgrade.token_file' => 'path to the token file, not the token',
    'validate_rbac_token.token_file'  => 'path to the token file, not the token',
    'rbac_token.token_lifetime'       => 'a duration such as 1y, not a token',
  }

  # Parameters that carry secrets although their names don't say so.
  always_sensitive = [
    # pe.conf with the console password, the r10k private key, the license
    # and the replica's keys.json files are written through it.
    'mkdir_p_file.content',
    # Can be a pre-signed URL with credentials in its query string.
    'download.source',
  ]

  # Tasks that take a flagged parameter as environment input anyway.
  environment_input_allowed = {
    'download' => 'PE-47901: download.sh still takes environment input',
  }

  metadata = Dir[File.expand_path('../../../tasks/*.json', __dir__)].sort.to_h do |path|
    [File.basename(path, '.json'), JSON.parse(File.read(path))]
  end
  specs_by_key = metadata.flat_map { |task, meta|
    (meta['parameters'] || {}).map { |name, spec| ["#{task}.#{name}", spec] }
  }.to_h
  secret_looking = ->(key) { key.split('.', 2).last.match?(secret_name) }
  checked = specs_by_key.select do |key, _spec|
    (secret_looking.call(key) || always_sensitive.include?(key)) && !not_secret.key?(key)
  end

  checked.each do |key, spec|
    it "flags #{key} as sensitive" do
      expect(spec['sensitive']).to be(true)
    end
  end

  # Bolt passes environment input on the remote command line
  # (`env PT_name=<value> ... sh -c ...`), unmasked even for a flagged
  # parameter: sudo logs that line on the node and ps shows it. Shell tasks
  # without an input_method get both stdin and environment.
  metadata.each do |task, meta|
    next unless (meta['parameters'] || {}).values.any? { |spec| spec['sensitive'] }
    next if environment_input_allowed.key?(task)

    it "gives #{task}, which takes a sensitive parameter, its input on stdin" do
      (meta['implementations'] || [{ 'name' => task }]).each do |impl|
        input_method = impl['input_method'] || meta['input_method'] || (impl['name'].end_with?('.ps1') ? 'powershell' : 'both')
        expect(['stdin', 'powershell']).to include(input_method), "#{impl['name']} takes #{input_method} input"
      end
    end
  end

  # Guards against the glob silently matching nothing, which would leave no
  # examples above and pass.
  it 'checks the parameters that leaked before PE-47523' do
    expect(checked.keys).to include('rbac_token.password', 'pe_ldap_config.ldap_config', 'mkdir_p_file.content', 'download.source')
  end

  it 'lists only existing tasks and parameters as exceptions' do
    expect(not_secret.keys + always_sensitive - specs_by_key.keys).to be_empty
    expect(environment_input_allowed.keys - metadata.keys).to be_empty
  end

  it 'lists only secret-looking names in not_secret' do
    expect(not_secret.keys.reject(&secret_looking)).to be_empty
  end

  it 'uses the same secret-name pattern as peadm::log_plan_parameters' do
    expect(File.read(File.expand_path('../../../functions/log_plan_parameters.pp', __dir__))).to include("/(?i:#{secret_name.source})/")
  end
end
