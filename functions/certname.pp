# @summary Return the certname of the given target-like input
#
# This function accepts a variety of data types which could represent single
# targets, and returns the certname corresponding to the input.
#
# For Target objects, or arrays of a single Target object, a "certname" var can
# be set, which determines that target's certname. Otherwise, the target's name
# is its certname. For strings, the certname is equal to the string. Undef
# input returns undef.
function peadm::certname(
  Variant[Target,
    String,
    Undef,
    Array[Target,1,1],
    Array[String,1,1],
    Array[Undef,1,1],
  Array[Any,0,0]] $target,
) >> Variant[String, Undef] {
# lint:ignore:unquoted_string_in_case
  case $target {
    Target: {
      $target.vars['certname'] ? {
        default => $target.vars['certname'],
        undef   => $target.name
      }
    }
    Array[Target,1,1]: {
      $target[0].vars['certname'] ? {
        default => $target[0].vars['certname'],
        undef   => $target[0].name
      }
# lint:endignore
    }
    String: {
      $target
    }
    Array[String,1,1]: {
      $target[0]
    }
    Undef, Array[Undef,1,1], Array[Any,0,0]: {
      undef
    }
    default: {
      fail('Unexpected input type to peadm::certname function')
    }
  }
}
