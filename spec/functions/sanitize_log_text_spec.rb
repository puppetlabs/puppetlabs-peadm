# frozen_string_literal: true

require 'spec_helper'

# Exists because plans/subplans/install.pp's rbac_token retry loop logs
# text from an external process's captured output on every retry (PE-46917).
# That text isn't guaranteed to be valid UTF-8 -- Bolt's stderr-capture path
# doesn't scrub encoding the way its stdout path does -- and Puppet's own
# regsubst/regex functions raise on invalid encoding rather than tolerating
# it, which would turn a transient rbac-service error into an unhandled
# plan-crashing evaluation error. `String#encode('UTF-8', invalid: :replace,
# undef: :replace, ...)` is what's guaranteed not to raise here: it handles
# both invalid-byte-sequence content AND content tagged with a different,
# non-ASCII-compatible encoding entirely (e.g. UTF-16LE) -- `String#scrub`
# alone only covers the first case and still raises Encoding::CompatibilityError
# on the second, since scrub's replacement string must be encoding-compatible
# with the receiver.
describe 'peadm::sanitize_log_text' do
  it 'replaces newlines and carriage returns with a single space' do
    is_expected.to run.with_params("line one\nline two\r\nline three", 200)
                      .and_return('line one line two line three')
  end

  it 'caps the result to max_length characters' do
    is_expected.to run.with_params('x' * 300, 200)
                      .and_return('x' * 200)
  end

  it 'returns a string shorter than max_length unchanged' do
    is_expected.to run.with_params('short error', 200)
                      .and_return('short error')
  end

  it 'returns a string exactly max_length long unchanged' do
    is_expected.to run.with_params('x' * 200, 200)
                      .and_return('x' * 200)
  end

  # Goes through the real dispatch path (`run.with_params`, not
  # `subject.execute`) deliberately -- the function exists because regex
  # matching requires valid encoding, so this needs to prove Puppet's own
  # `param 'String'` type-check doesn't itself reject invalid-UTF8 content
  # before the method body (that it doesn't) ever gets a chance to fix it.
  it 'replaces invalid UTF-8 byte sequences instead of raising' do
    invalid = "prefix \xFF\xFE invalid bytes here suffix".dup.force_encoding('UTF-8')
    expect(invalid.valid_encoding?).to eq(false) # sanity check the fixture is actually invalid

    is_expected.to run.with_params(invalid, 200).and_return(a_string_matching(%r{\Aprefix .. invalid bytes here suffix\z}))
  end

  it 'handles text tagged with a non-ASCII-compatible encoding instead of raising' do
    utf16 = 'hello'.encode('UTF-16LE')

    is_expected.to run.with_params(utf16, 200).and_return('hello')
  end

  # rubocop:disable RSpec/NamedSubject
  it 'rejects a negative max_length at the call boundary instead of returning Undef' do
    expect { subject.execute('hello', -1) }.to raise_error(ArgumentError, %r{expects an Integer\[0\] value})
  end
  # rubocop:enable RSpec/NamedSubject
end
