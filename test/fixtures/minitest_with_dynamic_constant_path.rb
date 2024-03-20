module Foo
end

module Bar
end

foo = rand > 0.5 ? Foo : Bar

module foo::Baz
  class Test < Minitest::Test
    def test_something; end
    
    def test_something_else; end

    class NestedTest < Minitest::Test
      def test_nested; end
    end
  end

  class SomeOtherTest < Minitest::Test
    def test_stuff; end

    def test_other_stuff; end

    module nested::Dynamic
      class OtherDynamicTest < Minitest::Test
        def test_more; end
      end
    end
  end
end
