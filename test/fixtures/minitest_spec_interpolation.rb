interpolation = "interpolation"

module Foo
end

describe Foo do
  describe "string_#{interpolation}" do
    it "does_something"

    describe "normal_string" do
      it "does_something_else"
    end
  end

  describe "#{interpolation}_double_string_#{interpolation}" do
    it "runs"

    it "runs_as_well"
  end

  it "it_level_one"
end
