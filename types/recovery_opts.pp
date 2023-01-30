type Peadm::Recovery_opts = Struct[{
    'orchestrator' => Optional[Boolean],
    'puppetdb'     => Optional[Boolean],
    'rbac'         => Optional[Boolean],
    'activity'     => Optional[Boolean],
    'ca'           => Optional[Boolean[false]],
    'classifier'   => Optional[Boolean],
}]
