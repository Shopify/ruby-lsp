# frozen_string_literal: true

class BogusSpec < Minitest::Spec
  describe "First Spec" do
    it "test one" do
      assert true
    end

    it "test two" do
      assert true
    end

    specify "test three" do
      assert true
    end

    describe "lorem ipsum" do
      it "dolor sit" do
        assert false
      end
    end
  end
end
