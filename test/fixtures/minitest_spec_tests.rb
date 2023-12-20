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
