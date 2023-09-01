type Peadm::Known_hosts = Array[
  Struct[
    'title'        => Optional[String[1]],
    'ensure'       => Optional[Enum['present','absent']],
    'name'         => String[1],
    'type'         => String[1],
    'key'          => String[1],
    'host_aliases' => Optional[Variant[String[1],Array[String[1]]]],
  ]
]
