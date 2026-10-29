# frozen_string_literal: true

require 'tempfile'

Puppet::Functions.create_function(:'peadm::file_content_upload') do
  local_types do
    type 'TargetOrTargets = Variant[String[1], Target, Array[TargetOrTargets]]'
  end

  dispatch :file_content_upload do
    param 'String[1]', :content
    param 'String[1]', :destination
    repeated_param 'TargetOrTargets', :targets
  end

  def file_content_upload(content, destination, *targets)
    file = Tempfile.new('peadm')
    file.write(content)
    file.flush
    call_function('upload_file', file.path, destination, *targets)
  ensure
    # Every caller uploads a pe.conf, and the primary's holds the console
    # password, so delete it from the Bolt host now, even when the upload
    # fails, instead of whenever Tempfile's finalizer runs (PE-47523).
    file&.close
    file&.unlink
  end
end
