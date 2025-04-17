# typed: true

class RubyIndexer::TestCase < Minitest::Test
  def initialize
    @index = nil #: RubyIndexer::Index # rubocop:disable Layout/LeadingCommentSpace
  end
end
