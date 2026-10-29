# @summary Read a file that can hold secrets, with Bolt masking its content in its logs where it can
#
# Bolt logs every task's result in bolt-debug.log. With as_sensitive,
# peadm::read_file returns the content under _sensitive, which Bolt masks in
# that log and in the task's result, and this function keeps it wrapped in
# Sensitive. Bolt's --stream option still prints the task's raw output,
# content included, and over the pcp transport Bolt doesn't mask _sensitive
# at all.
#
# @api private
#
# @param target The node to read the file on
# @param path The file to read
#
# @return [Optional[Sensitive[String]]] The file's content, or undef if it
#   doesn't exist or isn't readable. Fails if the read itself failed, so
#   callers never rewrite a file from content they didn't get.
function peadm::read_sensitive_file(
  Peadm::SingleTargetSpec $target,
  String[1]               $path,
) >> Optional[Sensitive[String]] {
  $result = run_task('peadm::read_file', get_target($target),
    path         => $path,
    as_sensitive => true,
  ).first

  # The pcp transport leaves _sensitive unwrapped, and runs the task from the
  # primary's deployed code, which can be an older peadm whose read_file
  # ignores as_sensitive and returns the content at the top level.
  $read = $result['_sensitive'] ? {
    Sensitive => $result['_sensitive'].unwrap,
    Hash      => $result['_sensitive'],
    default   => $result.value,
  }

  unless 'content' in $read {
    fail("Could not read ${path} on ${result.target.name}: peadm::read_file returned no content")
  }

  $read['content'] ? {
    undef   => undef,
    default => Sensitive($read['content']),
  }
}
