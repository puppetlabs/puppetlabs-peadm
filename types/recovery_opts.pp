# @summary Optional flags selecting the PE scopes to back up or restore
type Peadm::Recovery_opts = Struct[{
    'activity'     => Optional[Boolean],
    'ca'           => Optional[Boolean],
    'classifier'   => Optional[Boolean],
    'code'         => Optional[Boolean],
    'config'       => Optional[Boolean],
    'orchestrator' => Optional[Boolean],
    'puppetdb'     => Optional[Boolean],
    'rbac'         => Optional[Boolean],
}]
