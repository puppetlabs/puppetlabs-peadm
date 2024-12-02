require 'spec_helper'

describe 'peadm::migration_opts_default' do
  it 'returns pre 2023.7 defaults' do
    is_expected.to run.with_params('2023.6.0').and_return(
      {
        'activity'     => true,
        'ca'           => true,
        'classifier'   => true,
        'code'         => false,
        'config'       => false,
        'orchestrator' => true,
        'puppetdb'     => true,
        'rbac'         => true,
      },
    )
  end

  it 'returns 2023.7+ defaults with hac' do
    is_expected.to run.with_params('2023.7.0').and_return(
      {
        'activity'     => true,
        'ca'           => true,
        'classifier'   => true,
        'code'         => false,
        'config'       => false,
        'orchestrator' => true,
        'puppetdb'     => true,
        'rbac'         => true,
        'hac'          => true,
      },
    )
  end
end
