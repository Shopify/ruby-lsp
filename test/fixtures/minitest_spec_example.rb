# frozen_string_literal: true

require "minitest/spec"
require "minitest/autorun"

Minitest::Test.i_suck_and_my_tests_are_order_dependent!

class MySpec < Minitest::Spec
  describe "some scenario" do
    it "works as expected!" do
      assert_equal(1, 1)
    end

    # Anonymous example
    it do
      assert_equal(2, 2)
    end
  end
end
