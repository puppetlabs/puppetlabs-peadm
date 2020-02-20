require 'puppet_litmus'
require 'singleton'

class Helper
  include Singleton
  include PuppetLitmus
end

def some_helper_method
  Helper.instance.bolt_run_script('path/to/file')
end
