class Test < Minitest::Test
  private def test_private_command; end

  def test_public; end

  private

  public def test_public_command; end

  def test_private_vcall; end

  public

  def test_public_vcall; end
end
