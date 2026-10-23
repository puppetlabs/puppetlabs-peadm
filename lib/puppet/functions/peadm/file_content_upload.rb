# frozen_string_literal: true

require 'tempfile'

# @summary Upload inline content to a destination on one or more targets
Puppet::Functions.create_function(:'peadm::file_content_upload') do
  local_types do
    type 'TargetOrTargets = Variant[String[1], Target, Array[TargetOrTargets]]'
  end

  # @param content The file contents to upload.
  # @param destination The destination path on each target.
  # @param targets Targets to receive the file.
  # @return The result returned by upload_file.
  dispatch :file_content_upload do
    param 'String[1]', :content
    param 'String[1]', :destination
    repeated_param 'TargetOrTargets', :targets
  end

  def file_content_upload(content, destination, *targets)
    file = Tempfile.new('peadm')
    file.write(content)
    file.flush
    result = call_function('upload_file', file.path, destination, *targets)
    file.close
    file.unlink
    result
  end
end
