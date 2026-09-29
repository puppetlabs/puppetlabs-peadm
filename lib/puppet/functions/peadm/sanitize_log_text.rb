# frozen_string_literal: true

# @summary Makes arbitrary external text safe to interpolate into a single log line.
Puppet::Functions.create_function(:'peadm::sanitize_log_text') do
  # @param text Arbitrary text to make safe for a single log line -- may
  #   contain invalid byte sequences, or be tagged with a different,
  #   non-ASCII-compatible encoding entirely (e.g. from a captured
  #   subprocess's stderr), that Puppet's own regsubst/regex functions
  #   cannot safely operate on, since regex matching requires valid,
  #   ASCII-compatible encoding.
  # @param max_length Maximum length of the returned string.
  # @return A single-line, valid-UTF8, length-capped copy of `text`.
  dispatch :sanitize_log_text do
    param 'String', :text
    param 'Integer[0]', :max_length
    return_type 'String'
  end

  def sanitize_log_text(text, max_length)
    text.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?').gsub(%r{[\r\n]+}, ' ')[0, max_length]
  end
end
