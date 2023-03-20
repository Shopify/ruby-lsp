# typed: true
# frozen_string_literal: true

require "test_helper"

require "rubocop-minitest"
require "rubocop/minitest/assert_offense"

class UseLanguageServerAliasesTest < Minitest::Test
  include RuboCop::Minitest::AssertOffense

  def setup
    # Reload because Rubocop is unloaded by test/requests/formatting_test.rb
    # assert_offense calls RuboCop::RSpec::ExpectOffense::AnnotatedSource
    require "rubocop/rspec/expect_offense"

    @cop = ::RuboCop::Cop::RubyLsp::UseLanguageServerAliases.new
  end

  def test_registers_offense_when_using_interface_within_ruby_lsp
    assert_offense(<<~RUBY)
      module RubyLsp
        sig { override.returns(T.all(T::Array[LanguageServer::Protocol::Interface::FoldingRange], Object)) }
                                              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use constant alias `Interface`.
      end
    RUBY

    assert_correction(<<~RUBY)
      module RubyLsp
        sig { override.returns(T.all(T::Array[Interface::FoldingRange], Object)) }
      end
    RUBY
  end

  def test_does_not_register_offense_when_using_interface_outside_ruby_lsp
    assert_no_offenses(<<~RUBY)
      sig { override.returns(T.all(T::Array[LanguageServer::Protocol::Interface::FoldingRange], Object)) }
    RUBY
  end

  def test_registers_offense_when_using_transport_within_ruby_lsp
    assert_offense(<<~RUBY)
      module RubyLsp
        sig { override.returns(T.all(T::Array[LanguageServer::Protocol::Transport::FoldingRange], Object)) }
                                              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use constant alias `Transport`.
      end
    RUBY

    assert_correction(<<~RUBY)
      module RubyLsp
        sig { override.returns(T.all(T::Array[Transport::FoldingRange], Object)) }
      end
    RUBY
  end

  def test_does_not_register_offense_when_using_transport_outside_ruby_lsp
    assert_no_offenses(<<~RUBY)
      sig { override.returns(T.all(T::Array[LanguageServer::Protocol::Transport::FoldingRange], Object)) }
    RUBY
  end

  def test_registers_offense_when_using_constant_within_ruby_lsp
    assert_offense(<<~RUBY)
      module RubyLsp
        sig { override.returns(T.all(T::Array[LanguageServer::Protocol::Constant::FoldingRange], Object)) }
                                              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use constant alias `Constant`.
      end
    RUBY

    assert_correction(<<~RUBY)
      module RubyLsp
        sig { override.returns(T.all(T::Array[Constant::FoldingRange], Object)) }
      end
    RUBY
  end

  def test_does_not_register_offense_when_using_constant_outside_ruby_lsp
    assert_no_offenses(<<~RUBY)
      sig { override.returns(T.all(T::Array[LanguageServer::Protocol::Constant::FoldingRange], Object)) }
    RUBY
  end

  def test_registers_multiple_offenses
    assert_offense(<<~RUBY)
      module RubyLsp
        sig { override.returns(T.all(T::Array[LanguageServer::Protocol::Interface::FoldingRange], Object)) }
                                              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use constant alias `Interface`.
        sig { override.returns(T.all(T::Array[LanguageServer::Protocol::Transport::FoldingRange], Object)) }
                                              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use constant alias `Transport`.
        sig { override.returns(T.all(T::Array[LanguageServer::Protocol::Constant::FoldingRange], Object)) }
                                              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use constant alias `Constant`.
      end
    RUBY

    assert_correction(<<~RUBY)
      module RubyLsp
        sig { override.returns(T.all(T::Array[Interface::FoldingRange], Object)) }
        sig { override.returns(T.all(T::Array[Transport::FoldingRange], Object)) }
        sig { override.returns(T.all(T::Array[Constant::FoldingRange], Object)) }
      end
    RUBY
  end

  def test_does_not_register_offense
    assert_no_offenses(<<~RUBY)
      module RubyLsp
        Protocol = LanguageServer::Protocol
      end
    RUBY
  end

  def test_registers_the_correct_offense
    assert_offense(<<~RUBY)
      module RubyLsp
        sig { override.returns(T.all(T::Array[LanguageServer::Protocol::Interface::FoldingRange], Object)) }
                                              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use constant alias `Interface`.
      end
      sig { override.returns(T.all(T::Array[LanguageServer::Protocol::Transport::FoldingRange], Object)) }
    RUBY

    assert_correction(<<~RUBY)
      module RubyLsp
        sig { override.returns(T.all(T::Array[Interface::FoldingRange], Object)) }
      end
      sig { override.returns(T.all(T::Array[LanguageServer::Protocol::Transport::FoldingRange], Object)) }
    RUBY
  end

  def test_does_not_register_offense_when_using_unaliased_constant
    assert_no_offenses(<<~RUBY)
      sig { override.returns(T.all(T::Array[LanguageServer::Protocol::NewConst], Object)) }
    RUBY
  end
end
