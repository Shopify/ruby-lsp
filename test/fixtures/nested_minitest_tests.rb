class ParentTest < Minitest::Test
  def test_public; end

  private

  class FirstChildTest < Minitest::Test
    def test_public; end

    public
  end

  def test_private; end

  class SecondChildTest < Minitest::Test
    def test_public; end
  end

  public

  def test_public_again; end
end
