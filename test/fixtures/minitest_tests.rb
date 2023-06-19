class Test < Minitest::Test
  private def test_private_command; end

  private(def test_another_private; end)

  def test_public; end

  private

  public def test_public_command; end

  public(def test_another_public; end)

  def test_private_vcall; end

  public

  def test_public_vcall; end

  def test_with_q?; end

  private
end

class AnotherTest < Minitest::Test
  def test_public; end
end

class Foo
  def test_public; end
end
