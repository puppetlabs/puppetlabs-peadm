#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'puppet'
require_relative '../files/ica_task_helper'

# Bolt task: pin this compiler into the ICA classifier group and clear
# ca.conf's ica-pool. Nothing else: writing bootstrap.cfg and ca.conf's
# ica-* settings, and restarting the CA service in response to those
# writes, is profile::master's and profile::compiler_ica_ca's own job on
# the compiler's next Puppet run, not this task's. This task only sets the
# flags those classes act on, and clears the one ca.conf setting neither
# of them manages.
class PrepareIcaPromotion
  def initialize(params)
    @primary_host = params.fetch('primary_host')
  end

  def execute!
    classifier_https = IcaTaskHelper.primary_https_client(@primary_host, IcaTaskHelper::CLASSIFIER_PORT)
    IcaTaskHelper.pin_to_ica_group!(classifier_https, Puppet.settings[:certname])

    clear_ica_pool!

    STDOUT.puts({ 'status' => 'pinned' }.to_json)
    exit 0
  rescue StandardError => e
    warn "#{e.class}: #{e.message}"
    warn e.backtrace.first(10).join("\n") if e.backtrace
    IcaTaskHelper.emit_error!(e.message, 'peadm/prepare_ica_promotion_failed')
    exit 1
  end

  private

  ICA_POOL_ASSIGNMENT = %r{^[ \t]*ica-pool\s*[:=]\s*\[}.freeze

  def clear_ica_pool!
    path = IcaTaskHelper.ca_conf_path
    File.write(path, strip_ica_pool(File.read(path)))
  end

  # Removing a non-greedy match up to the first ']' is not enough: that
  # character can be a literal inside a quoted value (an IPv6 URL, for
  # instance) rather than the array's own close, so a naive strip can leave
  # an orphaned remainder of the value written into ca.conf without ever
  # tripping a bracket-count check, since the removed and orphaned text can
  # carry matching counts of their own. Scans forward from the array's
  # opening bracket instead, tracking quote state so a bracket inside a
  # quoted string is never mistaken for the array's own boundary.
  def strip_ica_pool(content)
    loop do
      match = content.match(ICA_POOL_ASSIGNMENT)
      break content unless match

      open_index = match.end(0) - 1
      close_index = matching_close_bracket_index(content, open_index)
      unless close_index
        raise 'Could not find a closing bracket for ica-pool in ca.conf - refusing to write a possibly-corrupt ca.conf; manual intervention required'
      end

      remove_through = close_index + 1
      remove_through += 1 if content[remove_through] == "\n"
      content = content[0...match.begin(0)] + content[remove_through..]
    end
  end

  def matching_close_bracket_index(content, open_index)
    depth = 1
    in_string = false
    escaped = false
    index = open_index + 1
    while index < content.length
      char = content[index]
      if in_string
        if escaped
          escaped = false # rubocop:disable Lint/UselessAssignment -- read at `if escaped` on the loop's next pass
        elsif char == '\\'
          escaped = true
        elsif char == '"'
          in_string = false # rubocop:disable Lint/UselessAssignment -- read at `if in_string` on the loop's next pass
        end
      else
        case char
        when '"' then in_string = true
        when '[' then depth += 1
        when ']'
          depth -= 1
          return index if depth.zero?
        end
      end
      index += 1
    end
    nil
  end
end

unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  PrepareIcaPromotion.new(JSON.parse(STDIN.read)).execute!
end
