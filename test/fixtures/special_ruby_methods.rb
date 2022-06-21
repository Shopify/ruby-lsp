# typed: true
# frozen_string_literal: true

require "foo"

class Bar
  include Baz
  attr_accessor(:bar)
  Kernel.extend Boz
  Kernel.include(Biz)
  protected

  def foo
    Buz.new
    method_call
  end
end
