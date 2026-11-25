#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'tempfile'

# Removes only top-level installation console passwords, without returning values.
class RemoveConsolePassword
  def self.clean(path, keys)
    path = File.expand_path(path)
    return { 'changed' => false, 'reason' => 'missing' } unless File.exist?(path) || File.symlink?(path)

    # Do not follow links to a running configuration or replace special files.
    raise 'Expected a regular file, not a symbolic link' if File.symlink?(path) || !File.file?(path)

    stat = File.stat(path)
    raise 'Refusing to modify a file with multiple hard links' unless stat.nlink == 1

    begin
      data = JSON.parse(File.read(path))
    rescue JSON::ParserError
      # Parser errors can contain snippets of the secret input.
      raise 'Expected a JSON object; the file was not modified'
    end
    raise 'Expected a JSON object; the file was not modified' unless data.is_a?(Hash)

    removed = keys.select { |key| data.key?(key) }
    return { 'changed' => false, 'reason' => 'no_console_password' } if removed.empty?

    removed.each { |key| data.delete(key) }
    Tempfile.create(['.peadm-cleanup-', '.json'], File.dirname(path)) do |file|
      file.write(JSON.pretty_generate(data) + "\n")
      file.flush
      file.fsync
      file.chown(stat.uid, stat.gid)
      file.chmod(stat.mode & 0o7777)
      File.rename(file.path, path)
    end
    { 'changed' => true, 'removed_keys' => removed }
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    # This task deliberately cannot accept an alternate primary config path.
    puts RemoveConsolePassword.clean('/tmp/pe.conf', ['console_admin_password']).to_json
  rescue StandardError
    # Never emit file contents, parser excerpts or secret values in task errors.
    puts({ '_error' => { 'kind' => 'peadm/secret_cleanup',
                        'msg' => 'Could not clean /tmp/pe.conf; expected an accessible regular JSON object file with one hard link.' } }).to_json
    exit 1
  end
end
