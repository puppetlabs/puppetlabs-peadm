function peadm::certname(
  Variant[Target,
          String,
          Undef,
          Array[Target,1,1],
          Array[String,1,1],
          Array[Undef,1,1],
          Array[Any,0,0]] $target,
) >> Variant[String, Undef] {
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
