# frozen_string_literal: true

require 'spec_helper'
require 'json'

# PE-47523: Bolt writes every task's arguments to bolt-debug.log at INFO
# ("Running task X with '<args as JSON>'"), the file operators attach to
# support cases. It masks only the parameters whose task metadata sets
# "sensitive": true, so a secret passed through any other parameter lands in
# that file in plaintext. These examples fail as soon as a task gains a
# parameter whose name looks like a secret without flagging it, or takes a
# flagged parameter as any input other than stdin.
#
# Limits: when every target uses the pcp transport, Bolt ignores task
# metadata, so the flag has no effect there. Task results are logged too;
# peadm::read_sensitive_file covers the reads that return secrets.
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

  # Implementations that take a flagged parameter as input other than stdin
  # anyway. Each one is listed on its own, so fixing one doesn't hide a
  # regression in the other.
  non_stdin_input_allowed = {
    'download.sh'  => 'PE-47901: environment input',
    'download.ps1' => 'PE-47901: powershell input',
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

  # The input method Bolt uses for each of a task's implementations
  input_methods = ->(task) do
    meta = metadata[task]
    (meta['implementations'] || [{ 'name' => task }]).map do |impl|
      bolt_default = impl['name'].end_with?('.ps1') ? 'powershell' : 'both'
      [impl['name'], impl['input_method'] || meta['input_method'] || bolt_default]
    end
  end

  input_by_implementation = metadata.keys.flat_map { |task| input_methods.call(task) }.to_h

  checked.each do |key, spec|
    it "flags #{key} as sensitive" do
      expect(spec['sensitive']).to be(true)
    end
  end

  # For the shell tasks peadm runs, only stdin keeps a value off the remote
  # command line. Bolt passes environment input as `env PT_name=<value> ...
  # sh -c ...`, unmasked even for a flagged parameter, where sudo logs it, ps
  # shows it and Bolt's own trace log records it. On PowerShell targets every
  # input method, stdin included (as a here-string), puts the value in the
  # command Bolt runs, so none keeps it off. An implementation with a
  # sensitive parameter is held to the stdin rule anyway; download.ps1 is
  # exempt until PE-47901.
  metadata.each do |task, meta|
    next unless (meta['parameters'] || {}).values.any? { |spec| spec['sensitive'] }

    input_methods.call(task).each do |name, input_method|
      next if non_stdin_input_allowed.key?(name)

      it "gives #{name}, which takes a sensitive parameter, its input on stdin" do
        expect(input_method).to eq('stdin'), "#{name} takes #{input_method} input"
      end
    end
  end

  # Guards against the glob silently matching nothing, which would leave no
  # examples above and pass.
  it 'checks the parameters known to carry secrets' do
    expect(checked.keys).to include('rbac_token.password', 'pe_ldap_config.ldap_config', 'mkdir_p_file.content', 'download.source')
  end

  it 'lists only existing tasks and parameters as exceptions' do
    expect(not_secret.keys + always_sensitive - specs_by_key.keys).to be_empty
    expect(non_stdin_input_allowed.keys - input_by_implementation.keys).to be_empty
  end

  it 'lists only secret-looking names in not_secret' do
    expect(not_secret.keys.reject(&secret_looking)).to be_empty
  end

  # So an exception doesn't outlive its fix and hide a later regression
  it 'lists only implementations that still take non-stdin input in non_stdin_input_allowed' do
    non_stdin_input_allowed.each_key do |name|
      expect(input_by_implementation[name]).not_to eq('stdin'), "#{name} no longer needs its exception"
    end
  end

  it 'uses the same secret-name pattern as peadm::log_plan_parameters' do
    expect(File.read(File.expand_path('../../../functions/log_plan_parameters.pp', __dir__))).to include("/(?i:#{secret_name.source})/")
  end
end
