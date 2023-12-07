# @summary converts two arrays into hash
# @param keys an array of key names to be merged into the hash
# @param values data to be merged into an array with the keys
# @example Using function
#   peadm::convert_hash(['type', 'status'], [['xl', 'running'], ['large', 'failed']])
#   [
#     { type => xl, status => running}, { type => large, status => failed }
#   ]
function peadm::convert_hash(Array $keys, Array[Array] $values) >> Array {
  $values.map |$out, $arr| {
    Hash(zip($keys,$arr))
  }
}
