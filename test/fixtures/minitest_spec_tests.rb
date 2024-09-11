describe Foo do
  it "it_level_one"

  describe "nested" do
    it "it_nested"

    describe "deep_nested" do
      it "it_deep_nested"
    end

    it "it_nested_again"
  end

  it "it_level_one_again"
end

describe Foo::Bar do
  it 'it_class_constant_path'
end

describe Baz do
  describe "#foo" do
    it "works"
  end

  describe "#bar" do
    it "works"
  end
end
