class WidgetTest < ActiveSupport::TestCase
  test "empty test" do
  end

  test "basic test" do
    assert true
  end

  test "interpolation before #{1+1} after" do
    assert true
  end

  test("single line block") { assert true }

  test("interpolation with parens, before #{1+1} after") do
    assert true
  end

  # the remaining should not be treated as test methods

  test "some" + "test" do
  end

  test :symbol_name do
  end

  it "does something" do
  end

  test do
  end

  test nil do
  end

  test "a", "b" do
  end

  test "" do
  end

  test "no block"

  test

  test() { assert true }

  test(nil) { assert true }

  test(foo) { assert true }
end
