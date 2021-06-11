# spec/spec_helper.rb

describe 'peadm::misc::divert_code_manager' do
  include BoltSpec::Plans

  describe 'basic functionality' do
    it 'runs successfully' do
      expect_task('peadm::divert_code_manager')
      expect(run_plan('peadm::misc::divert_code_manager', 'primary_host' => 'primary')).to be_ok
    end
  end
end
