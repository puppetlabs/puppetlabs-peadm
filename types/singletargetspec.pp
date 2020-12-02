# A SingleTargetSpec represents any String, Target or single-element array of
# one or the other that can be passed to get_targets() to return an
# Array[Target, 1, 1]. This is a constrained type variant of
# Boltlib::TargetSpec for use when a _single_ target is valid, but multiple
# targets are not.
type Peadm::SingleTargetSpec = Variant[
  Pattern[/\A[^[:space:],]+\z/],
  Target,
  Array[Peadm::SingleTargetSpec, 1, 1]
]
