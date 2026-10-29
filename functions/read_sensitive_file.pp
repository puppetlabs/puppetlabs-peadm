# @summary Read a file that can hold secrets, without Bolt logging its content
#
# Bolt logs every task's result in bolt-debug.log. peadm::read_file returns
# the content under _sensitive when asked, which Bolt masks there and in its
# output, and the content stays wrapped in Sensitive on the plan side
# (PE-47523).
#
# @param target The node to read the file on
# @param path The file to read
#
# @return [Optional[Sensitive[String]]] The file's content, or undef if it
#   doesn't exist or isn't readable
function peadm::read_sensitive_file(
  Peadm::SingleTargetSpec $target,
  String[1]               $path,
) >> Optional[Sensitive[String]] {
  $result = run_task('peadm::read_file', $target,
    path         => $path,
    as_sensitive => true,
  ).first.sensitive

  $content = $result ? {
    undef   => undef,
    default => $result.unwrap['content'],
  }

  $content ? {
    undef   => undef,
    default => Sensitive($content),
  }
}
