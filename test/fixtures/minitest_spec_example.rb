# frozen_string_literal: true

require "minitest/spec"
require "minitest/autorun"

Minitest::Spec.i_suck_and_my_tests_are_order_dependent!

module First
  module Second
    module Third
      class MySpec < Minitest::Spec
        # Anonymous example
        it do
          assert_equal(1, 1)
        end

        describe "when something is true" do
          describe "and other thing is false" do
            it "does what's expected" do
              assert(true)
            end
          end

          class NestedSpec < Minitest::Spec
            it "does something else" do
              assert(true)
            end
          end
        end
      end
    end
  end
end
