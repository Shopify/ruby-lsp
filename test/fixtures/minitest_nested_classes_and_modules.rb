module Foo
  class FooTest < Minitest::Test
    def test_foo; end

    def test_foo_2; end
  end

  module Bar
    class BarTest < Minitest::Test
      def test_bar; end

      module Baz
        class BazTest < Minitest::Test
          def test_baz; end

          def test_baz_2; end
        end
      end
    end
  end

  class Baz
    class BazTest < Minitest::Test
      def test_baz; end
    end
  end
end

module Foo::Bar
  class FooBarTest < Minitest::Test
    def test_foo_bar; end

    def test_foo_bar_2; end
  end

  module FooBar
  end

  class FooBar::Test < Minitest::Test
    def test_foo_bar_baz; end
  end
end
