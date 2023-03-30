# typed: strict

class SyntaxTree::Node
  # [Location] the location of this node
  sig { returns(SyntaxTree::Location) }
  attr_reader :location
end

# ARef represents when you're pulling a value out of a collection at a
# specific index. Put another way, it's any time you're calling the method
# #[].
#
#     collection[index]
#
# The nodes usually contains two children, the collection and the index. In
# some cases, you don't necessarily have the second child node, because you
# can call procs with a pretty esoteric syntax. In the following example, you
# wouldn't have a second child node:
#
#     collection[]
#
class SyntaxTree::ARef < SyntaxTree::Node
  # [Node] the value being indexed
  sig { returns(SyntaxTree::Node) }
  attr_reader :collection

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [nil | Args] the value being passed within the brackets
  sig { returns(T.nilable(SyntaxTree::Args)) }
  attr_reader :index

  sig do
    params(
      collection: SyntaxTree::Node,
      index: T.nilable(SyntaxTree::Args),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(collection:, index:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# ARefField represents assigning values into collections at specific indices.
# Put another way, it's any time you're calling the method #[]=. The
# ARefField node itself is just the left side of the assignment, and they're
# always wrapped in assign nodes.
#
#     collection[index] = value
#
class SyntaxTree::ARefField < SyntaxTree::Node
  # [Node] the value being indexed
  sig { returns(SyntaxTree::Node) }
  attr_reader :collection

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [nil | Args] the value being passed within the brackets
  sig { returns(T.nilable(SyntaxTree::Args)) }
  attr_reader :index

  sig do
    params(
      collection: SyntaxTree::Node,
      index: T.nilable(SyntaxTree::Args),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(collection:, index:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Alias represents the use of the +alias+ keyword with regular arguments (not
# global variables). The +alias+ keyword is used to make a method respond to
# another name as well as the current one.
#
#     alias aliased_name name
#
# For the example above, in the current context you can now call aliased_name
# and it will execute the name method. When you're aliasing two methods, you
# can either provide bare words (like the example above) or you can provide
# symbols (note that this includes dynamic symbols like
# :"left-#{middle}-right").
class SyntaxTree::AliasNode < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [DynaSymbol | GVar | SymbolLiteral] the new name of the method
  sig do
    returns(
      T.any(SyntaxTree::DynaSymbol, SyntaxTree::GVar, SyntaxTree::SymbolLiteral)
    )
  end
  attr_reader :left

  # [Backref | DynaSymbol | GVar | SymbolLiteral] the old name of the method
  sig do
    returns(
      T.any(
        SyntaxTree::Backref,
        SyntaxTree::DynaSymbol,
        SyntaxTree::GVar,
        SyntaxTree::SymbolLiteral
      )
    )
  end
  attr_reader :right

  sig do
    params(
      left:
        T.any(
          SyntaxTree::DynaSymbol,
          SyntaxTree::GVar,
          SyntaxTree::SymbolLiteral
        ),
      right:
        T.any(
          SyntaxTree::Backref,
          SyntaxTree::DynaSymbol,
          SyntaxTree::GVar,
          SyntaxTree::SymbolLiteral
        ),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(left:, right:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# ArgBlock represents using a block operator on an expression.
#
#     method(&expression)
#
class SyntaxTree::ArgBlock < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [nil | Node] the expression being turned into a block
  sig { returns(T.nilable(SyntaxTree::Node)) }
  attr_reader :value

  sig do
    params(
      value: T.nilable(SyntaxTree::Node),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# ArgParen represents wrapping arguments to a method inside a set of
# parentheses.
#
#     method(argument)
#
# In the example above, there would be an ArgParen node around the Args node
# that represents the set of arguments being sent to the method method. The
# argument child node can be +nil+ if no arguments were passed, as in:
#
#     method()
#
class SyntaxTree::ArgParen < SyntaxTree::Node
  # [nil | Args | ArgsForward] the arguments inside the
  # parentheses
  sig { returns(T.nilable(T.any(SyntaxTree::Args, SyntaxTree::ArgsForward))) }
  attr_reader :arguments

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  sig do
    params(
      arguments: T.nilable(T.any(SyntaxTree::Args, SyntaxTree::ArgsForward)),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(arguments:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Star represents using a splat operator on an expression.
#
#     method(*arguments)
#
class SyntaxTree::ArgStar < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [nil | Node] the expression being splatted
  sig { returns(T.nilable(SyntaxTree::Node)) }
  attr_reader :value

  sig do
    params(
      value: T.nilable(SyntaxTree::Node),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Args represents a list of arguments being passed to a method call or array
# literal.
#
#     method(first, second, third)
#
class SyntaxTree::Args < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Array[ Node ]] the arguments that this node wraps
  sig { returns(T::Array[SyntaxTree::Node]) }
  attr_reader :parts

  sig do
    params(
      parts: T::Array[SyntaxTree::Node],
      location: SyntaxTree::Location
    ).void
  end
  def initialize(parts:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# ArgsForward represents forwarding all kinds of arguments onto another method
# call.
#
#     def request(method, path, **headers, &block); end
#
#     def get(...)
#       request(:GET, ...)
#     end
#
#     def post(...)
#       request(:POST, ...)
#     end
#
# In the example above, both the get and post methods are forwarding all of
# their arguments (positional, keyword, and block) on to the request method.
# The ArgsForward node appears in both the caller (the request method calls)
# and the callee (the get and post definitions).
class SyntaxTree::ArgsForward < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  sig { params(location: SyntaxTree::Location).void }
  def initialize(location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# ArrayLiteral represents an array literal, which can optionally contain
# elements.
#
#     []
#     [one, two, three]
#
class SyntaxTree::ArrayLiteral < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [nil | Args] the contents of the array
  sig { returns(T.nilable(SyntaxTree::Args)) }
  attr_reader :contents

  # [nil | LBracket | QSymbolsBeg | QWordsBeg | SymbolsBeg | WordsBeg] the
  # bracket that opens this array
  sig do
    returns(
      T.nilable(
        T.any(
          SyntaxTree::LBracket,
          SyntaxTree::QSymbolsBeg,
          SyntaxTree::QWordsBeg,
          SyntaxTree::SymbolsBeg,
          SyntaxTree::WordsBeg
        )
      )
    )
  end
  attr_reader :lbracket

  sig do
    params(
      lbracket:
        T.nilable(
          T.any(
            SyntaxTree::LBracket,
            SyntaxTree::QSymbolsBeg,
            SyntaxTree::QWordsBeg,
            SyntaxTree::SymbolsBeg,
            SyntaxTree::WordsBeg
          )
        ),
      contents: T.nilable(SyntaxTree::Args),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(lbracket:, contents:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# AryPtn represents matching against an array pattern using the Ruby 2.7+
# pattern matching syntax. It’s one of the more complicated nodes, because
# the four parameters that it accepts can almost all be nil.
#
#     case [1, 2, 3]
#     in [Integer, Integer]
#       "matched"
#     in Container[Integer, Integer]
#       "matched"
#     in [Integer, *, Integer]
#       "matched"
#     end
#
# An AryPtn node is created with four parameters: an optional constant
# wrapper, an array of positional matches, an optional splat with identifier,
# and an optional array of positional matches that occur after the splat.
# All of the in clauses above would create an AryPtn node.
class SyntaxTree::AryPtn < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [nil | VarRef] the optional constant wrapper
  sig { returns(T.nilable(SyntaxTree::VarRef)) }
  attr_reader :constant

  # [Array[ Node ]] the list of positional arguments occurring after the
  # optional star if there is one
  sig { returns(T::Array[SyntaxTree::Node]) }
  attr_reader :posts

  # [Array[ Node ]] the regular positional arguments that this array
  # pattern is matching against
  sig { returns(T::Array[SyntaxTree::Node]) }
  attr_reader :requireds

  # [nil | VarField] the optional starred identifier that grabs up a list of
  # positional arguments
  sig { returns(T.nilable(SyntaxTree::VarField)) }
  attr_reader :rest

  sig do
    params(
      constant: T.nilable(SyntaxTree::VarRef),
      requireds: T::Array[SyntaxTree::Node],
      rest: T.nilable(SyntaxTree::VarField),
      posts: T::Array[SyntaxTree::Node],
      location: SyntaxTree::Location
    ).void
  end
  def initialize(constant:, requireds:, rest:, posts:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Assign represents assigning something to a variable or constant. Generally,
# the left side of the assignment is going to be any node that ends with the
# name "Field".
#
#     variable = value
#
class SyntaxTree::Assign < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [ARefField | ConstPathField | Field | TopConstField | VarField] the target
  # to assign the result of the expression to
  sig do
    returns(
      T.any(
        SyntaxTree::ARefField,
        SyntaxTree::ConstPathField,
        SyntaxTree::Field,
        SyntaxTree::TopConstField,
        SyntaxTree::VarField
      )
    )
  end
  attr_reader :target

  # [Node] the expression to be assigned
  sig { returns(SyntaxTree::Node) }
  attr_reader :value

  sig do
    params(
      target:
        T.any(
          SyntaxTree::ARefField,
          SyntaxTree::ConstPathField,
          SyntaxTree::Field,
          SyntaxTree::TopConstField,
          SyntaxTree::VarField
        ),
      value: SyntaxTree::Node,
      location: SyntaxTree::Location
    ).void
  end
  def initialize(target:, value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Assoc represents a key-value pair within a hash. It is a child node of
# either an AssocListFromArgs or a BareAssocHash.
#
#     { key1: value1, key2: value2 }
#
# In the above example, the would be two Assoc nodes.
class SyntaxTree::Assoc < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Node] the key of this pair
  sig { returns(SyntaxTree::Node) }
  attr_reader :key

  # [nil | Node] the value of this pair
  sig { returns(T.nilable(SyntaxTree::Node)) }
  attr_reader :value

  sig do
    params(
      key: SyntaxTree::Node,
      value: T.nilable(SyntaxTree::Node),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(key:, value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# AssocSplat represents double-splatting a value into a hash (either a hash
# literal or a bare hash in a method call).
#
#     { **pairs }
#
class SyntaxTree::AssocSplat < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [nil | Node] the expression that is being splatted
  sig { returns(T.nilable(SyntaxTree::Node)) }
  attr_reader :value

  sig do
    params(
      value: T.nilable(SyntaxTree::Node),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# BEGINBlock represents the use of the +BEGIN+ keyword, which hooks into the
# lifecycle of the interpreter. Whatever is inside the block will get executed
# when the program starts.
#
#     BEGIN {
#     }
#
# Interestingly, the BEGIN keyword doesn't allow the do and end keywords for
# the block. Only braces are permitted.
class SyntaxTree::BEGINBlock < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [LBrace] the left brace that is seen after the keyword
  sig { returns(SyntaxTree::LBrace) }
  attr_reader :lbrace

  # [Statements] the expressions to be executed
  sig { returns(SyntaxTree::Statements) }
  attr_reader :statements

  sig do
    params(
      lbrace: SyntaxTree::LBrace,
      statements: SyntaxTree::Statements,
      location: SyntaxTree::Location
    ).void
  end
  def initialize(lbrace:, statements:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Backref represents a global variable referencing a matched value. It comes
# in the form of a $ followed by a positive integer.
#
#     $1
#
class SyntaxTree::Backref < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [String] the name of the global backreference variable
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Backtick represents the use of the ` operator. It's usually found being used
# for an XStringLiteral, but could also be found as the name of a method being
# defined.
class SyntaxTree::Backtick < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [String] the backtick in the string
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# BareAssocHash represents a hash of contents being passed as a method
# argument (and therefore has omitted braces). It's very similar to an
# AssocListFromArgs node.
#
#     method(key1: value1, key2: value2)
#
class SyntaxTree::BareAssocHash < SyntaxTree::Node
  # [Array[ Assoc | AssocSplat ]]
  sig { returns(T::Array[T.any(SyntaxTree::Assoc, SyntaxTree::AssocSplat)]) }
  attr_reader :assocs

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  sig do
    params(
      assocs: T::Array[T.any(SyntaxTree::Assoc, SyntaxTree::AssocSplat)],
      location: SyntaxTree::Location
    ).void
  end
  def initialize(assocs:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Begin represents a begin..end chain.
#
#     begin
#       value
#     end
#
class SyntaxTree::Begin < SyntaxTree::Node
  # [BodyStmt] the bodystmt that contains the contents of this begin block
  sig { returns(SyntaxTree::BodyStmt) }
  attr_reader :bodystmt

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  sig do
    params(bodystmt: SyntaxTree::BodyStmt, location: SyntaxTree::Location).void
  end
  def initialize(bodystmt:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Binary represents any expression that involves two sub-expressions with an
# operator in between. This can be something that looks like a mathematical
# operation:
#
#     1 + 1
#
# but can also be something like pushing a value onto an array:
#
#     array << value
#
class SyntaxTree::Binary < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Node] the left-hand side of the expression
  sig { returns(SyntaxTree::Node) }
  attr_reader :left

  # [Symbol] the operator used between the two expressions
  sig { returns(Symbol) }
  attr_reader :operator

  # [Node] the right-hand side of the expression
  sig { returns(SyntaxTree::Node) }
  attr_reader :right

  sig do
    params(
      left: SyntaxTree::Node,
      operator: Symbol,
      right: SyntaxTree::Node,
      location: SyntaxTree::Location
    ).void
  end
  def initialize(left:, operator:, right:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# BlockArg represents declaring a block parameter on a method definition.
#
#     def method(&block); end
#
class SyntaxTree::BlockArg < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [nil | Ident] the name of the block argument
  sig { returns(T.nilable(SyntaxTree::Ident)) }
  attr_reader :name

  sig do
    params(
      name: T.nilable(SyntaxTree::Ident),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(name:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Block represents passing a block to a method call using the +do+ and +end+
# keywords or the +{+ and +}+ operators.
#
#     method do |value|
#     end
#
#     method { |value| }
#
class SyntaxTree::BlockNode < SyntaxTree::Node
  # [nil | BlockVar] the optional variable declaration within this block
  sig { returns(T.nilable(SyntaxTree::BlockVar)) }
  attr_reader :block_var

  # [BodyStmt | Statements] the expressions to be executed within this block
  sig { returns(T.any(SyntaxTree::BodyStmt, SyntaxTree::Statements)) }
  attr_reader :bodystmt

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [LBrace | Kw] the left brace or the do keyword that opens this block
  sig { returns(T.any(SyntaxTree::LBrace, SyntaxTree::Kw)) }
  attr_reader :opening

  sig do
    params(
      opening: T.any(SyntaxTree::LBrace, SyntaxTree::Kw),
      block_var: T.nilable(SyntaxTree::BlockVar),
      bodystmt: T.any(SyntaxTree::BodyStmt, SyntaxTree::Statements),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(opening:, block_var:, bodystmt:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# BlockVar represents the parameters being declared for a block. Effectively
# this node is everything contained within the pipes. This includes all of the
# various parameter types, as well as block-local variable declarations.
#
#     method do |positional, optional = value, keyword:, &block; local|
#     end
#
class SyntaxTree::BlockVar < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Array[ Ident ]] the list of block-local variable declarations
  sig { returns(T::Array[SyntaxTree::Ident]) }
  attr_reader :locals

  # [Params] the parameters being declared with the block
  sig { returns(SyntaxTree::Params) }
  attr_reader :params

  sig do
    params(
      params: SyntaxTree::Params,
      locals: T::Array[SyntaxTree::Ident],
      location: SyntaxTree::Location
    ).void
  end
  def initialize(params:, locals:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# bodystmt can't actually determine its bounds appropriately because it
# doesn't necessarily know where it started. So the parent node needs to
# report back down into this one where it goes.
class SyntaxTree::BodyStmt < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [nil | Statements] the optional set of statements inside the else clause
  sig { returns(T.nilable(SyntaxTree::Statements)) }
  attr_reader :else_clause

  # [nil | Kw] the optional else keyword
  sig { returns(T.nilable(SyntaxTree::Kw)) }
  attr_reader :else_keyword

  # [nil | Ensure] the optional ensure clause
  sig { returns(T.nilable(SyntaxTree::Ensure)) }
  attr_reader :ensure_clause

  # [nil | Rescue] the optional rescue chain attached to the begin clause
  sig { returns(T.nilable(SyntaxTree::Rescue)) }
  attr_reader :rescue_clause

  # [Statements] the list of statements inside the begin clause
  sig { returns(SyntaxTree::Statements) }
  attr_reader :statements

  sig do
    params(
      statements: SyntaxTree::Statements,
      rescue_clause: T.nilable(SyntaxTree::Rescue),
      else_keyword: T.nilable(SyntaxTree::Kw),
      else_clause: T.nilable(SyntaxTree::Statements),
      ensure_clause: T.nilable(SyntaxTree::Ensure),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(
    statements:,
    rescue_clause:,
    else_keyword:,
    else_clause:,
    ensure_clause:,
    location:
  )
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Break represents using the +break+ keyword.
#
#     break
#
# It can also optionally accept arguments, as in:
#
#     break 1
#
class SyntaxTree::Break < SyntaxTree::Node
  # [Args] the arguments being sent to the keyword
  sig { returns(SyntaxTree::Args) }
  attr_reader :arguments

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  sig do
    params(arguments: SyntaxTree::Args, location: SyntaxTree::Location).void
  end
  def initialize(arguments:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# CHAR irepresents a single codepoint in the script encoding.
#
#     ?a
#
# In the example above, the CHAR node represents the string literal "a". You
# can use control characters with this as well, as in ?\C-a.
class SyntaxTree::CHAR < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [String] the value of the character literal
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# CVar represents the use of a class variable.
#
#     @@variable
#
class SyntaxTree::CVar < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [String] the name of the class variable
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# CallNode represents a method call.
#
#     receiver.message
#
class SyntaxTree::CallNode < SyntaxTree::Node
  # [nil | ArgParen | Args] the arguments to the method call
  sig { returns(T.nilable(T.any(SyntaxTree::ArgParen, SyntaxTree::Args))) }
  attr_reader :arguments

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [:call | Backtick | Const | Ident | Op] the message being sent
  sig do
    returns(
      T.any(
        Symbol,
        SyntaxTree::Backtick,
        SyntaxTree::Const,
        SyntaxTree::Ident,
        SyntaxTree::Op
      )
    )
  end
  attr_reader :message

  # [nil | :"::" | Op | Period] the operator being used to send the message
  sig { returns(T.nilable(T.any(Symbol, SyntaxTree::Op, SyntaxTree::Period))) }
  attr_reader :operator

  # [nil | Node] the receiver of the method call
  sig { returns(T.nilable(SyntaxTree::Node)) }
  attr_reader :receiver

  sig do
    params(
      receiver: T.nilable(SyntaxTree::Node),
      operator: T.nilable(T.any(Symbol, SyntaxTree::Op, SyntaxTree::Period)),
      message:
        T.any(
          Symbol,
          SyntaxTree::Backtick,
          SyntaxTree::Const,
          SyntaxTree::Ident,
          SyntaxTree::Op
        ),
      arguments: T.nilable(T.any(SyntaxTree::ArgParen, SyntaxTree::Args)),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(receiver:, operator:, message:, arguments:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Case represents the beginning of a case chain.
#
#     case value
#     when 1
#       "one"
#     when 2
#       "two"
#     else
#       "number"
#     end
#
class SyntaxTree::Case < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [In | When] the next clause in the chain
  sig { returns(T.any(SyntaxTree::In, SyntaxTree::When)) }
  attr_reader :consequent

  # [Kw] the keyword that opens this expression
  sig { returns(SyntaxTree::Kw) }
  attr_reader :keyword

  # [nil | Node] optional value being switched on
  sig { returns(T.nilable(SyntaxTree::Node)) }
  attr_reader :value

  sig do
    params(
      keyword: SyntaxTree::Kw,
      value: T.nilable(SyntaxTree::Node),
      consequent: T.any(SyntaxTree::In, SyntaxTree::When),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(keyword:, value:, consequent:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Class represents defining a class using the +class+ keyword.
#
#     class Container
#     end
#
# Classes can have path names as their class name in case it's being nested
# under a namespace, as in:
#
#     class Namespace::Container
#     end
#
# Classes can also be defined as a top-level path, in the case that it's
# already in a namespace but you want to define it at the top-level instead,
# as in:
#
#     module OtherNamespace
#       class ::Namespace::Container
#       end
#     end
#
# All of these declarations can also have an optional superclass reference, as
# in:
#
#     class Child < Parent
#     end
#
# That superclass can actually be any Ruby expression, it doesn't necessarily
# need to be a constant, as in:
#
#     class Child < method
#     end
#
class SyntaxTree::ClassDeclaration < SyntaxTree::Node
  # [BodyStmt] the expressions to execute within the context of the class
  sig { returns(SyntaxTree::BodyStmt) }
  attr_reader :bodystmt

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [ConstPathRef | ConstRef | TopConstRef] the name of the class being
  # defined
  sig do
    returns(
      T.any(
        SyntaxTree::ConstPathRef,
        SyntaxTree::ConstRef,
        SyntaxTree::TopConstRef
      )
    )
  end
  attr_reader :constant

  # [nil | Node] the optional superclass declaration
  sig { returns(T.nilable(SyntaxTree::Node)) }
  attr_reader :superclass

  sig do
    params(
      constant:
        T.any(
          SyntaxTree::ConstPathRef,
          SyntaxTree::ConstRef,
          SyntaxTree::TopConstRef
        ),
      superclass: T.nilable(SyntaxTree::Node),
      bodystmt: SyntaxTree::BodyStmt,
      location: SyntaxTree::Location
    ).void
  end
  def initialize(constant:, superclass:, bodystmt:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Comma represents the use of the , operator.
class SyntaxTree::Comma < SyntaxTree::Node
  # [String] the comma in the string
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Command represents a method call with arguments and no parentheses. Note
# that Command nodes only happen when there is no explicit receiver for this
# method.
#
#     method argument
#
class SyntaxTree::Command < SyntaxTree::Node
  # [Args] the arguments being sent with the message
  sig { returns(SyntaxTree::Args) }
  attr_reader :arguments

  # [nil | BlockNode] the optional block being passed to the method
  sig { returns(T.nilable(SyntaxTree::BlockNode)) }
  attr_reader :block

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Const | Ident] the message being sent to the implicit receiver
  sig { returns(T.any(SyntaxTree::Const, SyntaxTree::Ident)) }
  attr_reader :message

  sig do
    params(
      message: T.any(SyntaxTree::Const, SyntaxTree::Ident),
      arguments: SyntaxTree::Args,
      block: T.nilable(SyntaxTree::BlockNode),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(message:, arguments:, block:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# CommandCall represents a method call on an object with arguments and no
# parentheses.
#
#     object.method argument
#
class SyntaxTree::CommandCall < SyntaxTree::Node
  # [nil | Args | ArgParen] the arguments going along with the message
  sig { returns(T.nilable(T.any(SyntaxTree::Args, SyntaxTree::ArgParen))) }
  attr_reader :arguments

  # [nil | BlockNode] the block associated with this method call
  sig { returns(T.nilable(SyntaxTree::BlockNode)) }
  attr_reader :block

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [:call | Const | Ident | Op] the message being send
  sig do
    returns(T.any(Symbol, SyntaxTree::Const, SyntaxTree::Ident, SyntaxTree::Op))
  end
  attr_reader :message

  # [nil | :"::" | Op | Period] the operator used to send the message
  sig { returns(T.nilable(T.any(Symbol, SyntaxTree::Op, SyntaxTree::Period))) }
  attr_reader :operator

  # [nil | Node] the receiver of the message
  sig { returns(T.nilable(SyntaxTree::Node)) }
  attr_reader :receiver

  sig do
    params(
      receiver: T.nilable(SyntaxTree::Node),
      operator: T.nilable(T.any(Symbol, SyntaxTree::Op, SyntaxTree::Period)),
      message:
        T.any(Symbol, SyntaxTree::Const, SyntaxTree::Ident, SyntaxTree::Op),
      arguments: T.nilable(T.any(SyntaxTree::Args, SyntaxTree::ArgParen)),
      block: T.nilable(SyntaxTree::BlockNode),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(receiver:, operator:, message:, arguments:, block:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Comment represents a comment in the source.
#
#     # comment
#
class SyntaxTree::Comment < SyntaxTree::Node
  # [boolean] whether or not there is code on the same line as this comment.
  # If there is, then inline will be true.
  sig { returns(T.any(TrueClass, FalseClass)) }
  attr_reader :inline

  # [String] the contents of the comment
  sig { returns(String) }
  attr_reader :value

  sig do
    params(
      value: String,
      inline: T.any(TrueClass, FalseClass),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(value:, inline:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Const represents a literal value that _looks_ like a constant. This could
# actually be a reference to a constant:
#
#     Constant
#
# It could also be something that looks like a constant in another context, as
# in a method call to a capitalized method:
#
#     object.Constant
#
# or a symbol that starts with a capital letter:
#
#     :Constant
#
class SyntaxTree::Const < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [String] the name of the constant
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# ConstPathField represents the child node of some kind of assignment. It
# represents when you're assigning to a constant that is being referenced as
# a child of another variable.
#
#     object::Const = value
#
class SyntaxTree::ConstPathField < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Const] the constant itself
  sig { returns(SyntaxTree::Const) }
  attr_reader :constant

  # [Node] the source of the constant
  sig { returns(SyntaxTree::Node) }
  attr_reader :parent

  sig do
    params(
      parent: SyntaxTree::Node,
      constant: SyntaxTree::Const,
      location: SyntaxTree::Location
    ).void
  end
  def initialize(parent:, constant:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# ConstPathRef represents referencing a constant by a path.
#
#     object::Const
#
class SyntaxTree::ConstPathRef < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Const] the constant itself
  sig { returns(SyntaxTree::Const) }
  attr_reader :constant

  # [Node] the source of the constant
  sig { returns(SyntaxTree::Node) }
  attr_reader :parent

  sig do
    params(
      parent: SyntaxTree::Node,
      constant: SyntaxTree::Const,
      location: SyntaxTree::Location
    ).void
  end
  def initialize(parent:, constant:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# ConstRef represents the name of the constant being used in a class or module
# declaration.
#
#     class Container
#     end
#
class SyntaxTree::ConstRef < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Const] the constant itself
  sig { returns(SyntaxTree::Const) }
  attr_reader :constant

  sig do
    params(constant: SyntaxTree::Const, location: SyntaxTree::Location).void
  end
  def initialize(constant:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Def represents defining a regular method on the current self object.
#
#     def method(param) result end
#     def object.method(param) result end
#
class SyntaxTree::DefNode < SyntaxTree::Node
  # [BodyStmt | Node] the expressions to be executed by the method
  sig { returns(T.any(SyntaxTree::BodyStmt, SyntaxTree::Node)) }
  attr_reader :bodystmt

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Backtick | Const | Ident | Kw | Op] the name of the method
  sig do
    returns(
      T.any(
        SyntaxTree::Backtick,
        SyntaxTree::Const,
        SyntaxTree::Ident,
        SyntaxTree::Kw,
        SyntaxTree::Op
      )
    )
  end
  attr_reader :name

  # [nil | Op | Period] the operator being used to declare the method
  sig { returns(T.nilable(T.any(SyntaxTree::Op, SyntaxTree::Period))) }
  attr_reader :operator

  # [nil | Params | Paren] the parameter declaration for the method
  sig { returns(T.nilable(T.any(SyntaxTree::Params, SyntaxTree::Paren))) }
  attr_reader :params

  # [nil | Node] the target where the method is being defined
  sig { returns(T.nilable(SyntaxTree::Node)) }
  attr_reader :target

  sig do
    params(
      target: T.nilable(SyntaxTree::Node),
      operator: T.nilable(T.any(SyntaxTree::Op, SyntaxTree::Period)),
      name:
        T.any(
          SyntaxTree::Backtick,
          SyntaxTree::Const,
          SyntaxTree::Ident,
          SyntaxTree::Kw,
          SyntaxTree::Op
        ),
      params: T.nilable(T.any(SyntaxTree::Params, SyntaxTree::Paren)),
      bodystmt: T.any(SyntaxTree::BodyStmt, SyntaxTree::Node),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(target:, operator:, name:, params:, bodystmt:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Defined represents the use of the +defined?+ operator. It can be used with
# and without parentheses.
#
#     defined?(variable)
#
class SyntaxTree::Defined < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Node] the value being sent to the keyword
  sig { returns(SyntaxTree::Node) }
  attr_reader :value

  sig { params(value: SyntaxTree::Node, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# DynaSymbol represents a symbol literal that uses quotes to dynamically
# define its value.
#
#     :"#{variable}"
#
# They can also be used as a special kind of dynamic hash key, as in:
#
#     { "#{key}": value }
#
class SyntaxTree::DynaSymbol < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Array[ StringDVar | StringEmbExpr | TStringContent ]] the parts of the
  # dynamic symbol
  sig do
    returns(
      T::Array[
        T.any(
          SyntaxTree::StringDVar,
          SyntaxTree::StringEmbExpr,
          SyntaxTree::TStringContent
        )
      ]
    )
  end
  attr_reader :parts

  # [nil | String] the quote used to delimit the dynamic symbol
  sig { returns(T.nilable(String)) }
  attr_reader :quote

  sig do
    params(
      parts:
        T::Array[
          T.any(
            SyntaxTree::StringDVar,
            SyntaxTree::StringEmbExpr,
            SyntaxTree::TStringContent
          )
        ],
      quote: T.nilable(String),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(parts:, quote:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# ENDBlock represents the use of the +END+ keyword, which hooks into the
# lifecycle of the interpreter. Whatever is inside the block will get executed
# when the program ends.
#
#     END {
#     }
#
# Interestingly, the END keyword doesn't allow the do and end keywords for the
# block. Only braces are permitted.
class SyntaxTree::ENDBlock < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [LBrace] the left brace that is seen after the keyword
  sig { returns(SyntaxTree::LBrace) }
  attr_reader :lbrace

  # [Statements] the expressions to be executed
  sig { returns(SyntaxTree::Statements) }
  attr_reader :statements

  sig do
    params(
      lbrace: SyntaxTree::LBrace,
      statements: SyntaxTree::Statements,
      location: SyntaxTree::Location
    ).void
  end
  def initialize(lbrace:, statements:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Else represents the end of an +if+, +unless+, or +case+ chain.
#
#     if variable
#     else
#     end
#
class SyntaxTree::Else < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Kw] the else keyword
  sig { returns(SyntaxTree::Kw) }
  attr_reader :keyword

  # [Statements] the expressions to be executed
  sig { returns(SyntaxTree::Statements) }
  attr_reader :statements

  sig do
    params(
      keyword: SyntaxTree::Kw,
      statements: SyntaxTree::Statements,
      location: SyntaxTree::Location
    ).void
  end
  def initialize(keyword:, statements:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Elsif represents another clause in an +if+ or +unless+ chain.
#
#     if variable
#     elsif other_variable
#     end
#
class SyntaxTree::Elsif < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [nil | Elsif | Else] the next clause in the chain
  sig { returns(T.nilable(T.any(SyntaxTree::Elsif, SyntaxTree::Else))) }
  attr_reader :consequent

  # [Node] the expression to be checked
  sig { returns(SyntaxTree::Node) }
  attr_reader :predicate

  # [Statements] the expressions to be executed
  sig { returns(SyntaxTree::Statements) }
  attr_reader :statements

  sig do
    params(
      predicate: SyntaxTree::Node,
      statements: SyntaxTree::Statements,
      consequent: T.nilable(T.any(SyntaxTree::Elsif, SyntaxTree::Else)),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(predicate:, statements:, consequent:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# EmbDoc represents a multi-line comment.
#
#     =begin
#     first line
#     second line
#     =end
#
class SyntaxTree::EmbDoc < SyntaxTree::Node
  # [String] the contents of the comment
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# EmbExprBeg represents the beginning token for using interpolation inside of
# a parent node that accepts string content (like a string or regular
# expression).
#
#     "Hello, #{person}!"
#
class SyntaxTree::EmbExprBeg < SyntaxTree::Node
  # [String] the #{ used in the string
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# EmbExprEnd represents the ending token for using interpolation inside of a
# parent node that accepts string content (like a string or regular
# expression).
#
#     "Hello, #{person}!"
#
class SyntaxTree::EmbExprEnd < SyntaxTree::Node
  # [String] the } used in the string
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# EmbVar represents the use of shorthand interpolation for an instance, class,
# or global variable into a parent node that accepts string content (like a
# string or regular expression).
#
#     "#@variable"
#
# In the example above, an EmbVar node represents the # because it forces
# @variable to be interpolated.
class SyntaxTree::EmbVar < SyntaxTree::Node
  # [String] the # used in the string
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# EndContent represents the use of __END__ syntax, which allows individual
# scripts to keep content after the main ruby code that can be read through
# the DATA constant.
#
#     puts DATA.read
#
#     __END__
#     some other content that is not executed by the program
#
class SyntaxTree::EndContent < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [String] the content after the script
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Ensure represents the use of the +ensure+ keyword and its subsequent
# statements.
#
#     begin
#     ensure
#     end
#
class SyntaxTree::Ensure < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Kw] the ensure keyword that began this node
  sig { returns(SyntaxTree::Kw) }
  attr_reader :keyword

  # [Statements] the expressions to be executed
  sig { returns(SyntaxTree::Statements) }
  attr_reader :statements

  sig do
    params(
      keyword: SyntaxTree::Kw,
      statements: SyntaxTree::Statements,
      location: SyntaxTree::Location
    ).void
  end
  def initialize(keyword:, statements:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# ExcessedComma represents a trailing comma in a list of block parameters. It
# changes the block parameters such that they will destructure.
#
#     [[1, 2, 3], [2, 3, 4]].each do |first, second,|
#     end
#
# In the above example, an ExcessedComma node would appear in the third
# position of the Params node that is used to declare that block. The third
# position typically represents a rest-type parameter, but in this case is
# used to indicate that a trailing comma was used.
class SyntaxTree::ExcessedComma < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [String] the comma
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Field is always the child of an assignment. It represents assigning to a
# “field” on an object.
#
#     object.variable = value
#
class SyntaxTree::Field < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Const | Ident] the name of the field being assigned
  sig { returns(T.any(SyntaxTree::Const, SyntaxTree::Ident)) }
  attr_reader :name

  # [:"::" | Op | Period] the operator being used for the assignment
  sig { returns(T.any(Symbol, SyntaxTree::Op, SyntaxTree::Period)) }
  attr_reader :operator

  # [Node] the parent object that owns the field being assigned
  sig { returns(SyntaxTree::Node) }
  attr_reader :parent

  sig do
    params(
      parent: SyntaxTree::Node,
      operator: T.any(Symbol, SyntaxTree::Op, SyntaxTree::Period),
      name: T.any(SyntaxTree::Const, SyntaxTree::Ident),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(parent:, operator:, name:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# FloatLiteral represents a floating point number literal.
#
#     1.0
#
class SyntaxTree::FloatLiteral < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [String] the value of the floating point number literal
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# FndPtn represents matching against a pattern where you find a pattern in an
# array using the Ruby 3.0+ pattern matching syntax.
#
#     case value
#     in [*, 7, *]
#     end
#
class SyntaxTree::FndPtn < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [nil | Node] the optional constant wrapper
  sig { returns(T.nilable(SyntaxTree::Node)) }
  attr_reader :constant

  # [VarField] the splat on the left-hand side
  sig { returns(SyntaxTree::VarField) }
  attr_reader :left

  # [VarField] the splat on the right-hand side
  sig { returns(SyntaxTree::VarField) }
  attr_reader :right

  # [Array[ Node ]] the list of positional expressions in the pattern that
  # are being matched
  sig { returns(T::Array[SyntaxTree::Node]) }
  attr_reader :values

  sig do
    params(
      constant: T.nilable(SyntaxTree::Node),
      left: SyntaxTree::VarField,
      values: T::Array[SyntaxTree::Node],
      right: SyntaxTree::VarField,
      location: SyntaxTree::Location
    ).void
  end
  def initialize(constant:, left:, values:, right:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# For represents using a +for+ loop.
#
#     for value in list do
#     end
#
class SyntaxTree::For < SyntaxTree::Node
  # [Node] the object being enumerated in the loop
  sig { returns(SyntaxTree::Node) }
  attr_reader :collection

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [MLHS | VarField] the variable declaration being used to
  # pull values out of the object being enumerated
  sig { returns(T.any(SyntaxTree::MLHS, SyntaxTree::VarField)) }
  attr_reader :index

  # [Statements] the statements to be executed
  sig { returns(SyntaxTree::Statements) }
  attr_reader :statements

  sig do
    params(
      index: T.any(SyntaxTree::MLHS, SyntaxTree::VarField),
      collection: SyntaxTree::Node,
      statements: SyntaxTree::Statements,
      location: SyntaxTree::Location
    ).void
  end
  def initialize(index:, collection:, statements:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# GVar represents a global variable literal.
#
#     $variable
#
class SyntaxTree::GVar < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [String] the name of the global variable
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# HashLiteral represents a hash literal.
#
#     { key => value }
#
class SyntaxTree::HashLiteral < SyntaxTree::Node
  # [Array[ Assoc | AssocSplat ]] the optional contents of the hash
  sig { returns(T::Array[T.any(SyntaxTree::Assoc, SyntaxTree::AssocSplat)]) }
  attr_reader :assocs

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [LBrace] the left brace that opens this hash
  sig { returns(SyntaxTree::LBrace) }
  attr_reader :lbrace

  sig do
    params(
      lbrace: SyntaxTree::LBrace,
      assocs: T::Array[T.any(SyntaxTree::Assoc, SyntaxTree::AssocSplat)],
      location: SyntaxTree::Location
    ).void
  end
  def initialize(lbrace:, assocs:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Heredoc represents a heredoc string literal.
#
#     <<~DOC
#       contents
#     DOC
#
class SyntaxTree::Heredoc < SyntaxTree::Node
  # [HeredocBeg] the opening of the heredoc
  sig { returns(SyntaxTree::HeredocBeg) }
  attr_reader :beginning

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Integer] how far to dedent the heredoc
  sig { returns(Integer) }
  attr_reader :dedent

  # [HeredocEnd] the ending of the heredoc
  sig { returns(SyntaxTree::HeredocEnd) }
  attr_reader :ending

  # [Array[ StringEmbExpr | StringDVar | TStringContent ]] the parts of the
  # heredoc string literal
  sig do
    returns(
      T::Array[
        T.any(
          SyntaxTree::StringEmbExpr,
          SyntaxTree::StringDVar,
          SyntaxTree::TStringContent
        )
      ]
    )
  end
  attr_reader :parts

  sig do
    params(
      beginning: SyntaxTree::HeredocBeg,
      location: SyntaxTree::Location,
      ending: SyntaxTree::HeredocEnd,
      dedent: Integer,
      parts:
        T::Array[
          T.any(
            SyntaxTree::StringEmbExpr,
            SyntaxTree::StringDVar,
            SyntaxTree::TStringContent
          )
        ]
    ).void
  end
  def initialize(
    beginning:,
    location:,
    ending: T.unsafe(nil),
    dedent: T.unsafe(nil),
    parts: T.unsafe(nil)
  )
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# HeredocBeg represents the beginning declaration of a heredoc.
#
#     <<~DOC
#       contents
#     DOC
#
# In the example above the HeredocBeg node represents <<~DOC.
class SyntaxTree::HeredocBeg < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [String] the opening declaration of the heredoc
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# HeredocEnd represents the closing declaration of a heredoc.
#
#     <<~DOC
#       contents
#     DOC
#
# In the example above the HeredocEnd node represents the closing DOC.
class SyntaxTree::HeredocEnd < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [String] the closing declaration of the heredoc
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# HshPtn represents matching against a hash pattern using the Ruby 2.7+
# pattern matching syntax.
#
#     case value
#     in { key: }
#     end
#
class SyntaxTree::HshPtn < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [nil | Node] the optional constant wrapper
  sig { returns(T.nilable(SyntaxTree::Node)) }
  attr_reader :constant

  # [nil | VarField] an optional parameter to gather up all remaining keywords
  sig { returns(T.nilable(SyntaxTree::VarField)) }
  attr_reader :keyword_rest

  # [Array[ [DynaSymbol | Label, nil | Node] ]] the set of tuples
  # representing the keywords that should be matched against in the pattern
  sig do
    returns(
      T::Array[
        [
          T.any(SyntaxTree::DynaSymbol, SyntaxTree::Label),
          T.nilable(SyntaxTree::Node)
        ]
      ]
    )
  end
  attr_reader :keywords

  sig do
    params(
      constant: T.nilable(SyntaxTree::Node),
      keywords:
        T::Array[
          [
            T.any(SyntaxTree::DynaSymbol, SyntaxTree::Label),
            T.nilable(SyntaxTree::Node)
          ]
        ],
      keyword_rest: T.nilable(SyntaxTree::VarField),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(constant:, keywords:, keyword_rest:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# IVar represents an instance variable literal.
#
#     @variable
#
class SyntaxTree::IVar < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [String] the name of the instance variable
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Ident represents an identifier anywhere in code. It can represent a very
# large number of things, depending on where it is in the syntax tree.
#
#     value
#
class SyntaxTree::Ident < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [String] the value of the identifier
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# If represents the first clause in an +if+ chain.
#
#     if predicate
#     end
#
class SyntaxTree::IfNode < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [nil | Elsif | Else] the next clause in the chain
  sig { returns(T.nilable(T.any(SyntaxTree::Elsif, SyntaxTree::Else))) }
  attr_reader :consequent

  # [Node] the expression to be checked
  sig { returns(SyntaxTree::Node) }
  attr_reader :predicate

  # [Statements] the expressions to be executed
  sig { returns(SyntaxTree::Statements) }
  attr_reader :statements

  sig do
    params(
      predicate: SyntaxTree::Node,
      statements: SyntaxTree::Statements,
      consequent: T.nilable(T.any(SyntaxTree::Elsif, SyntaxTree::Else)),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(predicate:, statements:, consequent:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# IfOp represents a ternary clause.
#
#     predicate ? truthy : falsy
#
class SyntaxTree::IfOp < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Node] the expression to be executed if the predicate is falsy
  sig { returns(SyntaxTree::Node) }
  attr_reader :falsy

  # [Node] the expression to be checked
  sig { returns(SyntaxTree::Node) }
  attr_reader :predicate

  # [Node] the expression to be executed if the predicate is truthy
  sig { returns(SyntaxTree::Node) }
  attr_reader :truthy

  sig do
    params(
      predicate: SyntaxTree::Node,
      truthy: SyntaxTree::Node,
      falsy: SyntaxTree::Node,
      location: SyntaxTree::Location
    ).void
  end
  def initialize(predicate:, truthy:, falsy:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Imaginary represents an imaginary number literal.
#
#     1i
#
class SyntaxTree::Imaginary < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [String] the value of the imaginary number literal
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# In represents using the +in+ keyword within the Ruby 2.7+ pattern matching
# syntax.
#
#     case value
#     in pattern
#     end
#
class SyntaxTree::In < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [nil | In | Else] the next clause in the chain
  sig { returns(T.nilable(T.any(SyntaxTree::In, SyntaxTree::Else))) }
  attr_reader :consequent

  # [Node] the pattern to check against
  sig { returns(SyntaxTree::Node) }
  attr_reader :pattern

  # [Statements] the expressions to execute if the pattern matched
  sig { returns(SyntaxTree::Statements) }
  attr_reader :statements

  sig do
    params(
      pattern: SyntaxTree::Node,
      statements: SyntaxTree::Statements,
      consequent: T.nilable(T.any(SyntaxTree::In, SyntaxTree::Else)),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(pattern:, statements:, consequent:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Int represents an integer number literal.
#
#     1
#
class SyntaxTree::Int < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [String] the value of the integer
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Kw represents the use of a keyword. It can be almost anywhere in the syntax
# tree, so you end up seeing it quite a lot.
#
#     if value
#     end
#
# In the above example, there would be two Kw nodes: one for the if and one
# for the end. Note that anything that matches the list of keywords in Ruby
# will use a Kw, so if you use a keyword in a symbol literal for instance:
#
#     :if
#
# then the contents of the symbol node will contain a Kw node.
class SyntaxTree::Kw < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Symbol] the symbol version of the value
  sig { returns(Symbol) }
  attr_reader :name

  # [String] the value of the keyword
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# KwRestParam represents defining a parameter in a method definition that
# accepts all remaining keyword parameters.
#
#     def method(**kwargs) end
#
class SyntaxTree::KwRestParam < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [nil | Ident] the name of the parameter
  sig { returns(T.nilable(SyntaxTree::Ident)) }
  attr_reader :name

  sig do
    params(
      name: T.nilable(SyntaxTree::Ident),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(name:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# LBrace represents the use of a left brace, i.e., {.
class SyntaxTree::LBrace < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [String] the left brace
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# LBracket represents the use of a left bracket, i.e., [.
class SyntaxTree::LBracket < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [String] the left bracket
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# LParen represents the use of a left parenthesis, i.e., (.
class SyntaxTree::LParen < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [String] the left parenthesis
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Label represents the use of an identifier to associate with an object. You
# can find it in a hash key, as in:
#
#     { key: value }
#
# In this case "key:" would be the body of the label. You can also find it in
# pattern matching, as in:
#
#     case value
#     in key:
#     end
#
# In this case "key:" would be the body of the label.
class SyntaxTree::Label < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [String] the value of the label
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# LabelEnd represents the end of a dynamic symbol.
#
#     { "key": value }
#
# In the example above, LabelEnd represents the "\":" token at the end of the
# hash key. This node is important for determining the type of quote being
# used by the label.
class SyntaxTree::LabelEnd < SyntaxTree::Node
  # [String] the end of the label
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Lambda represents using a lambda literal (not the lambda method call).
#
#     ->(value) { value * 2 }
#
class SyntaxTree::Lambda < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [LambdaVar | Paren] the parameter declaration for this lambda
  sig { returns(T.any(SyntaxTree::LambdaVar, SyntaxTree::Paren)) }
  attr_reader :params

  # [BodyStmt | Statements] the expressions to be executed in this lambda
  sig { returns(T.any(SyntaxTree::BodyStmt, SyntaxTree::Statements)) }
  attr_reader :statements

  sig do
    params(
      params: T.any(SyntaxTree::LambdaVar, SyntaxTree::Paren),
      statements: T.any(SyntaxTree::BodyStmt, SyntaxTree::Statements),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(params:, statements:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# LambdaVar represents the parameters being declared for a lambda. Effectively
# this node is everything contained within the parentheses. This includes all
# of the various parameter types, as well as block-local variable
# declarations.
#
#     -> (positional, optional = value, keyword:, &block; local) do
#     end
#
class SyntaxTree::LambdaVar < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Array[ Ident ]] the list of block-local variable declarations
  sig { returns(T::Array[SyntaxTree::Ident]) }
  attr_reader :locals

  # [Params] the parameters being declared with the block
  sig { returns(SyntaxTree::Params) }
  attr_reader :params

  sig do
    params(
      params: SyntaxTree::Params,
      locals: T::Array[SyntaxTree::Ident],
      location: SyntaxTree::Location
    ).void
  end
  def initialize(params:, locals:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# MAssign is a parent node of any kind of multiple assignment. This includes
# splitting out variables on the left like:
#
#     first, second, third = value
#
# as well as splitting out variables on the right, as in:
#
#     value = first, second, third
#
# Both sides support splats, as well as variables following them. There's also
# destructuring behavior that you can achieve with the following:
#
#     first, = value
#
class SyntaxTree::MAssign < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [MLHS | MLHSParen] the target of the multiple assignment
  sig { returns(T.any(SyntaxTree::MLHS, SyntaxTree::MLHSParen)) }
  attr_reader :target

  # [Node] the value being assigned
  sig { returns(SyntaxTree::Node) }
  attr_reader :value

  sig do
    params(
      target: T.any(SyntaxTree::MLHS, SyntaxTree::MLHSParen),
      value: SyntaxTree::Node,
      location: SyntaxTree::Location
    ).void
  end
  def initialize(target:, value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# MLHS represents a list of values being destructured on the left-hand side
# of a multiple assignment.
#
#     first, second, third = value
#
class SyntaxTree::MLHS < SyntaxTree::Node
  # [boolean] whether or not there is a trailing comma at the end of this
  # list, which impacts destructuring. It's an attr_accessor so that while
  # the syntax tree is being built it can be set by its parent node
  sig { returns(T.any(TrueClass, FalseClass)) }
  attr_reader :comma

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [
  #   Array[
  #     ARefField | ArgStar | ConstPathField | Field | Ident | MLHSParen |
  #       TopConstField | VarField
  #   ]
  # ] the parts of the left-hand side of a multiple assignment
  sig do
    returns(
      T::Array[
        T.any(
          SyntaxTree::ARefField,
          SyntaxTree::ArgStar,
          SyntaxTree::ConstPathField,
          SyntaxTree::Field,
          SyntaxTree::Ident,
          SyntaxTree::MLHSParen,
          SyntaxTree::TopConstField,
          SyntaxTree::VarField
        )
      ]
    )
  end
  attr_reader :parts

  sig do
    params(
      parts:
        T::Array[
          T.any(
            SyntaxTree::ARefField,
            SyntaxTree::ArgStar,
            SyntaxTree::ConstPathField,
            SyntaxTree::Field,
            SyntaxTree::Ident,
            SyntaxTree::MLHSParen,
            SyntaxTree::TopConstField,
            SyntaxTree::VarField
          )
        ],
      location: SyntaxTree::Location,
      comma: T.any(TrueClass, FalseClass)
    ).void
  end
  def initialize(parts:, location:, comma: T.unsafe(nil))
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# MLHSParen represents parentheses being used to destruct values in a multiple
# assignment on the left hand side.
#
#     (left, right) = value
#
class SyntaxTree::MLHSParen < SyntaxTree::Node
  # [boolean] whether or not there is a trailing comma at the end of this
  # list, which impacts destructuring. It's an attr_accessor so that while
  # the syntax tree is being built it can be set by its parent node
  sig { returns(T.any(TrueClass, FalseClass)) }
  attr_reader :comma

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [MLHS | MLHSParen] the contents inside of the parentheses
  sig { returns(T.any(SyntaxTree::MLHS, SyntaxTree::MLHSParen)) }
  attr_reader :contents

  sig do
    params(
      contents: T.any(SyntaxTree::MLHS, SyntaxTree::MLHSParen),
      location: SyntaxTree::Location,
      comma: T.any(TrueClass, FalseClass)
    ).void
  end
  def initialize(contents:, location:, comma: T.unsafe(nil))
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# MRHS represents the values that are being assigned on the right-hand side of
# a multiple assignment.
#
#     values = first, second, third
#
class SyntaxTree::MRHS < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Array[Node]] the parts that are being assigned
  sig { returns(T::Array[SyntaxTree::Node]) }
  attr_reader :parts

  sig do
    params(
      parts: T::Array[SyntaxTree::Node],
      location: SyntaxTree::Location
    ).void
  end
  def initialize(parts:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# MethodAddBlock represents a method call with a block argument.
#
#     method {}
#
class SyntaxTree::MethodAddBlock < SyntaxTree::Node
  # [BlockNode] the block being sent with the method call
  sig { returns(SyntaxTree::BlockNode) }
  attr_reader :block

  # [ARef | CallNode | Command | CommandCall | Super | ZSuper] the method call
  sig do
    returns(
      T.any(
        SyntaxTree::ARef,
        SyntaxTree::CallNode,
        SyntaxTree::Command,
        SyntaxTree::CommandCall,
        SyntaxTree::Super,
        SyntaxTree::ZSuper
      )
    )
  end
  attr_reader :call

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  sig do
    params(
      call:
        T.any(
          SyntaxTree::ARef,
          SyntaxTree::CallNode,
          SyntaxTree::Command,
          SyntaxTree::CommandCall,
          SyntaxTree::Super,
          SyntaxTree::ZSuper
        ),
      block: SyntaxTree::BlockNode,
      location: SyntaxTree::Location
    ).void
  end
  def initialize(call:, block:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# ModuleDeclaration represents defining a module using the +module+ keyword.
#
#     module Namespace
#     end
#
class SyntaxTree::ModuleDeclaration < SyntaxTree::Node
  # [BodyStmt] the expressions to be executed in the context of the module
  sig { returns(SyntaxTree::BodyStmt) }
  attr_reader :bodystmt

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [ConstPathRef | ConstRef | TopConstRef] the name of the module
  sig do
    returns(
      T.any(
        SyntaxTree::ConstPathRef,
        SyntaxTree::ConstRef,
        SyntaxTree::TopConstRef
      )
    )
  end
  attr_reader :constant

  sig do
    params(
      constant:
        T.any(
          SyntaxTree::ConstPathRef,
          SyntaxTree::ConstRef,
          SyntaxTree::TopConstRef
        ),
      bodystmt: SyntaxTree::BodyStmt,
      location: SyntaxTree::Location
    ).void
  end
  def initialize(constant:, bodystmt:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Next represents using the +next+ keyword.
#
#     next
#
# The +next+ keyword can also optionally be called with an argument:
#
#     next value
#
# +next+ can even be called with multiple arguments, but only if parentheses
# are omitted, as in:
#
#     next first, second, third
#
# If a single value is being given, parentheses can be used, as in:
#
#     next(value)
#
class SyntaxTree::Next < SyntaxTree::Node
  # [Args] the arguments passed to the next keyword
  sig { returns(SyntaxTree::Args) }
  attr_reader :arguments

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  sig do
    params(arguments: SyntaxTree::Args, location: SyntaxTree::Location).void
  end
  def initialize(arguments:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Not represents the unary +not+ method being called on an expression.
#
#     not value
#
class SyntaxTree::Not < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [boolean] whether or not parentheses were used
  sig { returns(T.any(TrueClass, FalseClass)) }
  attr_reader :parentheses

  # [nil | Node] the statement on which to operate
  sig { returns(T.nilable(SyntaxTree::Node)) }
  attr_reader :statement

  sig do
    params(
      statement: T.nilable(SyntaxTree::Node),
      parentheses: T.any(TrueClass, FalseClass),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(statement:, parentheses:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Op represents an operator literal in the source.
#
#     1 + 2
#
# In the example above, the Op node represents the + operator.
class SyntaxTree::Op < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Symbol] the symbol version of the value
  sig { returns(Symbol) }
  attr_reader :name

  # [String] the operator
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# OpAssign represents assigning a value to a variable or constant using an
# operator like += or ||=.
#
#     variable += value
#
class SyntaxTree::OpAssign < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Op] the operator being used for the assignment
  sig { returns(SyntaxTree::Op) }
  attr_reader :operator

  # [ARefField | ConstPathField | Field | TopConstField | VarField] the target
  # to assign the result of the expression to
  sig do
    returns(
      T.any(
        SyntaxTree::ARefField,
        SyntaxTree::ConstPathField,
        SyntaxTree::Field,
        SyntaxTree::TopConstField,
        SyntaxTree::VarField
      )
    )
  end
  attr_reader :target

  # [Node] the expression to be assigned
  sig { returns(SyntaxTree::Node) }
  attr_reader :value

  sig do
    params(
      target:
        T.any(
          SyntaxTree::ARefField,
          SyntaxTree::ConstPathField,
          SyntaxTree::Field,
          SyntaxTree::TopConstField,
          SyntaxTree::VarField
        ),
      operator: SyntaxTree::Op,
      value: SyntaxTree::Node,
      location: SyntaxTree::Location
    ).void
  end
  def initialize(target:, operator:, value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# def on_operator_ambiguous(value)
#   value
# end
# Params represents defining parameters on a method or lambda.
#
#     def method(param) end
#
class SyntaxTree::Params < SyntaxTree::Node
  # [nil | BlockArg] the optional block parameter
  sig { returns(T.nilable(SyntaxTree::BlockArg)) }
  attr_reader :block

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [nil | :nil | ArgsForward | KwRestParam] the optional keyword rest
  # parameter
  sig do
    returns(
      T.nilable(T.any(Symbol, SyntaxTree::ArgsForward, SyntaxTree::KwRestParam))
    )
  end
  attr_reader :keyword_rest

  # [Array[ [ Label, nil | Node ] ]] any keyword parameters and their
  # optional default values
  sig { returns(T::Array[[SyntaxTree::Label, T.nilable(SyntaxTree::Node)]]) }
  attr_reader :keywords

  # [Array[ [ Ident, Node ] ]] any optional parameters and their default
  # values
  sig { returns(T::Array[[SyntaxTree::Ident, SyntaxTree::Node]]) }
  attr_reader :optionals

  # [Array[ Ident ]] any positional parameters that exist after a rest
  # parameter
  sig { returns(T::Array[SyntaxTree::Ident]) }
  attr_reader :posts

  # [Array[ Ident | MLHSParen ]] any required parameters
  sig { returns(T::Array[T.any(SyntaxTree::Ident, SyntaxTree::MLHSParen)]) }
  attr_reader :requireds

  # [nil | ArgsForward | ExcessedComma | RestParam] the optional rest
  # parameter
  sig do
    returns(
      T.nilable(
        T.any(
          SyntaxTree::ArgsForward,
          SyntaxTree::ExcessedComma,
          SyntaxTree::RestParam
        )
      )
    )
  end
  attr_reader :rest

  sig do
    params(
      location: SyntaxTree::Location,
      requireds: T::Array[T.any(SyntaxTree::Ident, SyntaxTree::MLHSParen)],
      optionals: T::Array[[SyntaxTree::Ident, SyntaxTree::Node]],
      rest:
        T.nilable(
          T.any(
            SyntaxTree::ArgsForward,
            SyntaxTree::ExcessedComma,
            SyntaxTree::RestParam
          )
        ),
      posts: T::Array[SyntaxTree::Ident],
      keywords: T::Array[[SyntaxTree::Label, T.nilable(SyntaxTree::Node)]],
      keyword_rest:
        T.nilable(
          T.any(Symbol, SyntaxTree::ArgsForward, SyntaxTree::KwRestParam)
        ),
      block: T.nilable(SyntaxTree::BlockArg)
    ).void
  end
  def initialize(
    location:,
    requireds: T.unsafe(nil),
    optionals: T.unsafe(nil),
    rest: T.unsafe(nil),
    posts: T.unsafe(nil),
    keywords: T.unsafe(nil),
    keyword_rest: T.unsafe(nil),
    block: T.unsafe(nil)
  )
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Paren represents using balanced parentheses in a couple places in a Ruby
# program. In general parentheses can be used anywhere a Ruby expression can
# be used.
#
#     (1 + 2)
#
class SyntaxTree::Paren < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [nil | Node] the expression inside the parentheses
  sig { returns(T.nilable(SyntaxTree::Node)) }
  attr_reader :contents

  # [LParen] the left parenthesis that opened this statement
  sig { returns(SyntaxTree::LParen) }
  attr_reader :lparen

  sig do
    params(
      lparen: SyntaxTree::LParen,
      contents: T.nilable(SyntaxTree::Node),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(lparen:, contents:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Period represents the use of the +.+ operator. It is usually found in method
# calls.
class SyntaxTree::Period < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [String] the period
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# PinnedBegin represents a pinning a nested statement within pattern matching.
#
#     case value
#     in ^(statement)
#     end
#
class SyntaxTree::PinnedBegin < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Node] the expression being pinned
  sig { returns(SyntaxTree::Node) }
  attr_reader :statement

  sig do
    params(statement: SyntaxTree::Node, location: SyntaxTree::Location).void
  end
  def initialize(statement:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# PinnedVarRef represents a pinned variable reference within a pattern
# matching pattern.
#
#     case value
#     in ^variable
#     end
#
# This can be a plain local variable like the example above. It can also be a
# a class variable, a global variable, or an instance variable.
class SyntaxTree::PinnedVarRef < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Const | CVar | GVar | Ident | IVar] the value of this node
  sig do
    returns(
      T.any(
        SyntaxTree::Const,
        SyntaxTree::CVar,
        SyntaxTree::GVar,
        SyntaxTree::Ident,
        SyntaxTree::IVar
      )
    )
  end
  attr_reader :value

  sig do
    params(
      value:
        T.any(
          SyntaxTree::Const,
          SyntaxTree::CVar,
          SyntaxTree::GVar,
          SyntaxTree::Ident,
          SyntaxTree::IVar
        ),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Program represents the overall syntax tree.
class SyntaxTree::Program < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Statements] the top-level expressions of the program
  sig { returns(SyntaxTree::Statements) }
  attr_reader :statements

  sig do
    params(
      statements: SyntaxTree::Statements,
      location: SyntaxTree::Location
    ).void
  end
  def initialize(statements:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# QSymbols represents a symbol literal array without interpolation.
#
#     %i[one two three]
#
class SyntaxTree::QSymbols < SyntaxTree::Node
  # [QSymbolsBeg] the token that opens this array literal
  sig { returns(SyntaxTree::QSymbolsBeg) }
  attr_reader :beginning

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Array[ TStringContent ]] the elements of the array
  sig { returns(T::Array[SyntaxTree::TStringContent]) }
  attr_reader :elements

  sig do
    params(
      beginning: SyntaxTree::QSymbolsBeg,
      elements: T::Array[SyntaxTree::TStringContent],
      location: SyntaxTree::Location
    ).void
  end
  def initialize(beginning:, elements:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# QSymbolsBeg represents the beginning of a symbol literal array.
#
#     %i[one two three]
#
# In the snippet above, QSymbolsBeg represents the "%i[" token. Note that
# these kinds of arrays can start with a lot of different delimiter types
# (e.g., %i| or %i<).
class SyntaxTree::QSymbolsBeg < SyntaxTree::Node
  # [String] the beginning of the array literal
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# QWords represents a string literal array without interpolation.
#
#     %w[one two three]
#
class SyntaxTree::QWords < SyntaxTree::Node
  # [QWordsBeg] the token that opens this array literal
  sig { returns(SyntaxTree::QWordsBeg) }
  attr_reader :beginning

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Array[ TStringContent ]] the elements of the array
  sig { returns(T::Array[SyntaxTree::TStringContent]) }
  attr_reader :elements

  sig do
    params(
      beginning: SyntaxTree::QWordsBeg,
      elements: T::Array[SyntaxTree::TStringContent],
      location: SyntaxTree::Location
    ).void
  end
  def initialize(beginning:, elements:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# QWordsBeg represents the beginning of a string literal array.
#
#     %w[one two three]
#
# In the snippet above, QWordsBeg represents the "%w[" token. Note that these
# kinds of arrays can start with a lot of different delimiter types (e.g.,
# %w| or %w<).
class SyntaxTree::QWordsBeg < SyntaxTree::Node
  # [String] the beginning of the array literal
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# RAssign represents a single-line pattern match.
#
#     value in pattern
#     value => pattern
#
class SyntaxTree::RAssign < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Kw | Op] the operator being used to match against the pattern, which is
  # either => or in
  sig { returns(T.any(SyntaxTree::Kw, SyntaxTree::Op)) }
  attr_reader :operator

  # [Node] the pattern on the right-hand side of the expression
  sig { returns(SyntaxTree::Node) }
  attr_reader :pattern

  # [Node] the left-hand expression
  sig { returns(SyntaxTree::Node) }
  attr_reader :value

  sig do
    params(
      value: SyntaxTree::Node,
      operator: T.any(SyntaxTree::Kw, SyntaxTree::Op),
      pattern: SyntaxTree::Node,
      location: SyntaxTree::Location
    ).void
  end
  def initialize(value:, operator:, pattern:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# RBrace represents the use of a right brace, i.e., +++.
class SyntaxTree::RBrace < SyntaxTree::Node
  # [String] the right brace
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# RBracket represents the use of a right bracket, i.e., +]+.
class SyntaxTree::RBracket < SyntaxTree::Node
  # [String] the right bracket
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# RParen represents the use of a right parenthesis, i.e., +)+.
class SyntaxTree::RParen < SyntaxTree::Node
  # [String] the parenthesis
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# RangeNode represents using the .. or the ... operator between two
# expressions. Usually this is to create a range object.
#
#     1..2
#
# Sometimes this operator is used to create a flip-flop.
#
#     if value == 5 .. value == 10
#     end
#
# One of the sides of the expression may be nil, but not both.
class SyntaxTree::RangeNode < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [nil | Node] the left side of the expression
  sig { returns(T.nilable(SyntaxTree::Node)) }
  attr_reader :left

  # [Op] the operator used for this range
  sig { returns(SyntaxTree::Op) }
  attr_reader :operator

  # [nil | Node] the right side of the expression
  sig { returns(T.nilable(SyntaxTree::Node)) }
  attr_reader :right

  sig do
    params(
      left: T.nilable(SyntaxTree::Node),
      operator: SyntaxTree::Op,
      right: T.nilable(SyntaxTree::Node),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(left:, operator:, right:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# RationalLiteral represents the use of a rational number literal.
#
#     1r
#
class SyntaxTree::RationalLiteral < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [String] the rational number literal
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Redo represents the use of the +redo+ keyword.
#
#     redo
#
class SyntaxTree::Redo < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  sig { params(location: SyntaxTree::Location).void }
  def initialize(location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# RegexpBeg represents the start of a regular expression literal.
#
#     /.+/
#
# In the example above, RegexpBeg represents the first / token. Regular
# expression literals can also be declared using the %r syntax, as in:
#
#     %r{.+}
#
class SyntaxTree::RegexpBeg < SyntaxTree::Node
  # [String] the beginning of the regular expression
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# RegexpContent represents the body of a regular expression.
#
#     /.+ #{pattern} .+/
#
# In the example above, a RegexpContent node represents everything contained
# within the forward slashes.
class SyntaxTree::RegexpContent < SyntaxTree::Node
  # [String] the opening of the regular expression
  sig { returns(String) }
  attr_reader :beginning

  # [Array[ StringDVar | StringEmbExpr | TStringContent ]] the parts of the
  # regular expression
  sig do
    returns(
      T::Array[
        T.any(
          SyntaxTree::StringDVar,
          SyntaxTree::StringEmbExpr,
          SyntaxTree::TStringContent
        )
      ]
    )
  end
  attr_reader :parts

  sig do
    params(
      beginning: String,
      parts:
        T::Array[
          T.any(
            SyntaxTree::StringDVar,
            SyntaxTree::StringEmbExpr,
            SyntaxTree::TStringContent
          )
        ],
      location: SyntaxTree::Location
    ).void
  end
  def initialize(beginning:, parts:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# RegexpEnd represents the end of a regular expression literal.
#
#     /.+/m
#
# In the example above, the RegexpEnd event represents the /m at the end of
# the regular expression literal. You can also declare regular expression
# literals using %r, as in:
#
#     %r{.+}m
#
class SyntaxTree::RegexpEnd < SyntaxTree::Node
  # [String] the end of the regular expression
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# RegexpLiteral represents a regular expression literal.
#
#     /.+/
#
class SyntaxTree::RegexpLiteral < SyntaxTree::Node
  # [String] the beginning of the regular expression literal
  sig { returns(String) }
  attr_reader :beginning

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [String] the ending of the regular expression literal
  sig { returns(String) }
  attr_reader :ending

  # [Array[ StringEmbExpr | StringDVar | TStringContent ]] the parts of the
  # regular expression literal
  sig do
    returns(
      T::Array[
        T.any(
          SyntaxTree::StringEmbExpr,
          SyntaxTree::StringDVar,
          SyntaxTree::TStringContent
        )
      ]
    )
  end
  attr_reader :parts

  sig do
    params(
      beginning: String,
      ending: String,
      parts:
        T::Array[
          T.any(
            SyntaxTree::StringEmbExpr,
            SyntaxTree::StringDVar,
            SyntaxTree::TStringContent
          )
        ],
      location: SyntaxTree::Location
    ).void
  end
  def initialize(beginning:, ending:, parts:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Rescue represents the use of the rescue keyword inside of a BodyStmt node.
#
#     begin
#     rescue
#     end
#
class SyntaxTree::Rescue < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [nil | Rescue] the optional next clause in the chain
  sig { returns(T.nilable(SyntaxTree::Rescue)) }
  attr_reader :consequent

  # [nil | RescueEx] the exceptions being rescued
  sig { returns(T.nilable(SyntaxTree::RescueEx)) }
  attr_reader :exception

  # [Kw] the rescue keyword
  sig { returns(SyntaxTree::Kw) }
  attr_reader :keyword

  # [Statements] the expressions to evaluate when an error is rescued
  sig { returns(SyntaxTree::Statements) }
  attr_reader :statements

  sig do
    params(
      keyword: SyntaxTree::Kw,
      exception: T.nilable(SyntaxTree::RescueEx),
      statements: SyntaxTree::Statements,
      consequent: T.nilable(SyntaxTree::Rescue),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(keyword:, exception:, statements:, consequent:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# RescueEx represents the list of exceptions being rescued in a rescue clause.
#
#     begin
#     rescue Exception => exception
#     end
#
class SyntaxTree::RescueEx < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [nil | Node] the list of exceptions being rescued
  sig { returns(T.nilable(SyntaxTree::Node)) }
  attr_reader :exceptions

  # [nil | Field | VarField] the expression being used to capture the raised
  # exception
  sig { returns(T.nilable(T.any(SyntaxTree::Field, SyntaxTree::VarField))) }
  attr_reader :variable

  sig do
    params(
      exceptions: T.nilable(SyntaxTree::Node),
      variable: T.nilable(T.any(SyntaxTree::Field, SyntaxTree::VarField)),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(exceptions:, variable:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# RescueMod represents the use of the modifier form of a +rescue+ clause.
#
#     expression rescue value
#
class SyntaxTree::RescueMod < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Node] the expression to execute
  sig { returns(SyntaxTree::Node) }
  attr_reader :statement

  # [Node] the value to use if the executed expression raises an error
  sig { returns(SyntaxTree::Node) }
  attr_reader :value

  sig do
    params(
      statement: SyntaxTree::Node,
      value: SyntaxTree::Node,
      location: SyntaxTree::Location
    ).void
  end
  def initialize(statement:, value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# RestParam represents defining a parameter in a method definition that
# accepts all remaining positional parameters.
#
#     def method(*rest) end
#
class SyntaxTree::RestParam < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [nil | Ident] the name of the parameter
  sig { returns(T.nilable(SyntaxTree::Ident)) }
  attr_reader :name

  sig do
    params(
      name: T.nilable(SyntaxTree::Ident),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(name:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Retry represents the use of the +retry+ keyword.
#
#     retry
#
class SyntaxTree::Retry < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  sig { params(location: SyntaxTree::Location).void }
  def initialize(location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Return represents using the +return+ keyword with arguments.
#
#     return value
#
class SyntaxTree::ReturnNode < SyntaxTree::Node
  # [nil | Args] the arguments being passed to the keyword
  sig { returns(T.nilable(SyntaxTree::Args)) }
  attr_reader :arguments

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  sig do
    params(
      arguments: T.nilable(SyntaxTree::Args),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(arguments:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# SClass represents a block of statements that should be evaluated within the
# context of the singleton class of an object. It's frequently used to define
# singleton methods.
#
#     class << self
#     end
#
class SyntaxTree::SClass < SyntaxTree::Node
  # [BodyStmt] the expressions to be executed
  sig { returns(SyntaxTree::BodyStmt) }
  attr_reader :bodystmt

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Node] the target of the singleton class to enter
  sig { returns(SyntaxTree::Node) }
  attr_reader :target

  sig do
    params(
      target: SyntaxTree::Node,
      bodystmt: SyntaxTree::BodyStmt,
      location: SyntaxTree::Location
    ).void
  end
  def initialize(target:, bodystmt:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Everything that has a block of code inside of it has a list of statements.
# Normally we would just track those as a node that has an array body, but we
# have some special handling in order to handle empty statement lists. They
# need to have the right location information, so all of the parent node of
# stmts nodes will report back down the location information. We then
# propagate that onto void_stmt nodes inside the stmts in order to make sure
# all comments get printed appropriately.
class SyntaxTree::Statements < SyntaxTree::Node
  # [Array[ Node ]] the list of expressions contained within this node
  sig { returns(T::Array[SyntaxTree::Node]) }
  attr_reader :body

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  sig do
    params(
      body: T::Array[SyntaxTree::Node],
      location: SyntaxTree::Location
    ).void
  end
  def initialize(body:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# StringConcat represents concatenating two strings together using a backward
# slash.
#
#     "first" \
#       "second"
#
class SyntaxTree::StringConcat < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Heredoc | StringConcat | StringLiteral] the left side of the
  # concatenation
  sig do
    returns(
      T.any(
        SyntaxTree::Heredoc,
        SyntaxTree::StringConcat,
        SyntaxTree::StringLiteral
      )
    )
  end
  attr_reader :left

  # [StringLiteral] the right side of the concatenation
  sig { returns(SyntaxTree::StringLiteral) }
  attr_reader :right

  sig do
    params(
      left:
        T.any(
          SyntaxTree::Heredoc,
          SyntaxTree::StringConcat,
          SyntaxTree::StringLiteral
        ),
      right: SyntaxTree::StringLiteral,
      location: SyntaxTree::Location
    ).void
  end
  def initialize(left:, right:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# StringContent represents the contents of a string-like value.
#
#     "string"
#
class SyntaxTree::StringContent < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Array[ StringEmbExpr | StringDVar | TStringContent ]] the parts of the
  # string
  sig do
    returns(
      T::Array[
        T.any(
          SyntaxTree::StringEmbExpr,
          SyntaxTree::StringDVar,
          SyntaxTree::TStringContent
        )
      ]
    )
  end
  attr_reader :parts

  sig do
    params(
      parts:
        T::Array[
          T.any(
            SyntaxTree::StringEmbExpr,
            SyntaxTree::StringDVar,
            SyntaxTree::TStringContent
          )
        ],
      location: SyntaxTree::Location
    ).void
  end
  def initialize(parts:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# StringDVar represents shorthand interpolation of a variable into a string.
# It allows you to take an instance variable, class variable, or global
# variable and omit the braces when interpolating.
#
#     "#@variable"
#
class SyntaxTree::StringDVar < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Backref | VarRef] the variable being interpolated
  sig { returns(T.any(SyntaxTree::Backref, SyntaxTree::VarRef)) }
  attr_reader :variable

  sig do
    params(
      variable: T.any(SyntaxTree::Backref, SyntaxTree::VarRef),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(variable:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# StringEmbExpr represents interpolated content. It can be contained within a
# couple of different parent nodes, including regular expressions, strings,
# and dynamic symbols.
#
#     "string #{expression}"
#
class SyntaxTree::StringEmbExpr < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Statements] the expressions to be interpolated
  sig { returns(SyntaxTree::Statements) }
  attr_reader :statements

  sig do
    params(
      statements: SyntaxTree::Statements,
      location: SyntaxTree::Location
    ).void
  end
  def initialize(statements:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# StringLiteral represents a string literal.
#
#     "string"
#
class SyntaxTree::StringLiteral < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Array[ StringEmbExpr | StringDVar | TStringContent ]] the parts of the
  # string literal
  sig do
    returns(
      T::Array[
        T.any(
          SyntaxTree::StringEmbExpr,
          SyntaxTree::StringDVar,
          SyntaxTree::TStringContent
        )
      ]
    )
  end
  attr_reader :parts

  # [nil | String] which quote was used by the string literal
  sig { returns(T.nilable(String)) }
  attr_reader :quote

  sig do
    params(
      parts:
        T::Array[
          T.any(
            SyntaxTree::StringEmbExpr,
            SyntaxTree::StringDVar,
            SyntaxTree::TStringContent
          )
        ],
      quote: T.nilable(String),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(parts:, quote:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Super represents using the +super+ keyword with arguments. It can optionally
# use parentheses.
#
#     super(value)
#
class SyntaxTree::Super < SyntaxTree::Node
  # [ArgParen | Args] the arguments to the keyword
  sig { returns(T.any(SyntaxTree::ArgParen, SyntaxTree::Args)) }
  attr_reader :arguments

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  sig do
    params(
      arguments: T.any(SyntaxTree::ArgParen, SyntaxTree::Args),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(arguments:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# SymBeg represents the beginning of a symbol literal.
#
#     :symbol
#
# SymBeg is also used for dynamic symbols, as in:
#
#     :"symbol"
#
# Finally, SymBeg is also used for symbols using the %s syntax, as in:
#
#     %s[symbol]
#
# The value of this node is a string. In most cases (as in the first example
# above) it will contain just ":". In the case of dynamic symbols it will
# contain ":'" or ":\"". In the case of %s symbols, it will contain the start
# of the symbol including the %s and the delimiter.
class SyntaxTree::SymBeg < SyntaxTree::Node
  # [String] the beginning of the symbol
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# SymbolContent represents symbol contents and is always the child of a
# SymbolLiteral node.
#
#     :symbol
#
class SyntaxTree::SymbolContent < SyntaxTree::Node
  # [Backtick | Const | CVar | GVar | Ident | IVar | Kw | Op] the value of the
  # symbol
  sig do
    returns(
      T.any(
        SyntaxTree::Backtick,
        SyntaxTree::Const,
        SyntaxTree::CVar,
        SyntaxTree::GVar,
        SyntaxTree::Ident,
        SyntaxTree::IVar,
        SyntaxTree::Kw,
        SyntaxTree::Op
      )
    )
  end
  attr_reader :value

  sig do
    params(
      value:
        T.any(
          SyntaxTree::Backtick,
          SyntaxTree::Const,
          SyntaxTree::CVar,
          SyntaxTree::GVar,
          SyntaxTree::Ident,
          SyntaxTree::IVar,
          SyntaxTree::Kw,
          SyntaxTree::Op
        ),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# SymbolLiteral represents a symbol in the system with no interpolation
# (as opposed to a DynaSymbol which has interpolation).
#
#     :symbol
#
class SyntaxTree::SymbolLiteral < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Backtick | Const | CVar | GVar | Ident | IVar | Kw | Op | TStringContent]
  # the value of the symbol
  sig do
    returns(
      T.any(
        SyntaxTree::Backtick,
        SyntaxTree::Const,
        SyntaxTree::CVar,
        SyntaxTree::GVar,
        SyntaxTree::Ident,
        SyntaxTree::IVar,
        SyntaxTree::Kw,
        SyntaxTree::Op,
        SyntaxTree::TStringContent
      )
    )
  end
  attr_reader :value

  sig do
    params(
      value:
        T.any(
          SyntaxTree::Backtick,
          SyntaxTree::Const,
          SyntaxTree::CVar,
          SyntaxTree::GVar,
          SyntaxTree::Ident,
          SyntaxTree::IVar,
          SyntaxTree::Kw,
          SyntaxTree::Op,
          SyntaxTree::TStringContent
        ),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Symbols represents a symbol array literal with interpolation.
#
#     %I[one two three]
#
class SyntaxTree::Symbols < SyntaxTree::Node
  # [SymbolsBeg] the token that opens this array literal
  sig { returns(SyntaxTree::SymbolsBeg) }
  attr_reader :beginning

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Array[ Word ]] the words in the symbol array literal
  sig { returns(T::Array[SyntaxTree::Word]) }
  attr_reader :elements

  sig do
    params(
      beginning: SyntaxTree::SymbolsBeg,
      elements: T::Array[SyntaxTree::Word],
      location: SyntaxTree::Location
    ).void
  end
  def initialize(beginning:, elements:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# SymbolsBeg represents the start of a symbol array literal with
# interpolation.
#
#     %I[one two three]
#
# In the snippet above, SymbolsBeg represents the "%I[" token. Note that these
# kinds of arrays can start with a lot of different delimiter types
# (e.g., %I| or %I<).
class SyntaxTree::SymbolsBeg < SyntaxTree::Node
  # [String] the beginning of the symbol literal array
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# TLamBeg represents the beginning of the body of a lambda literal using
# braces.
#
#     -> { value }
#
# In the example above the TLamBeg represents the +{+ operator.
class SyntaxTree::TLamBeg < SyntaxTree::Node
  # [String] the beginning of the body of the lambda literal
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# TLambda represents the beginning of a lambda literal.
#
#     -> { value }
#
# In the example above the TLambda represents the +->+ operator.
class SyntaxTree::TLambda < SyntaxTree::Node
  # [String] the beginning of the lambda literal
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# TStringBeg represents the beginning of a string literal.
#
#     "string"
#
# In the example above, TStringBeg represents the first set of quotes. Strings
# can also use single quotes. They can also be declared using the +%q+ and
# +%Q+ syntax, as in:
#
#     %q{string}
#
class SyntaxTree::TStringBeg < SyntaxTree::Node
  # [String] the beginning of the string
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# TStringContent represents plain characters inside of an entity that accepts
# string content like a string, heredoc, command string, or regular
# expression.
#
#     "string"
#
# In the example above, TStringContent represents the +string+ token contained
# within the string.
class SyntaxTree::TStringContent < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [String] the content of the string
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# TStringEnd represents the end of a string literal.
#
#     "string"
#
# In the example above, TStringEnd represents the second set of quotes.
# Strings can also use single quotes. They can also be declared using the +%q+
# and +%Q+ syntax, as in:
#
#     %q{string}
#
class SyntaxTree::TStringEnd < SyntaxTree::Node
  # [String] the end of the string
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# TopConstField is always the child node of some kind of assignment. It
# represents when you're assigning to a constant that is being referenced at
# the top level.
#
#     ::Constant = value
#
class SyntaxTree::TopConstField < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Const] the constant being assigned
  sig { returns(SyntaxTree::Const) }
  attr_reader :constant

  sig do
    params(constant: SyntaxTree::Const, location: SyntaxTree::Location).void
  end
  def initialize(constant:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# TopConstRef is very similar to TopConstField except that it is not involved
# in an assignment.
#
#     ::Constant
#
class SyntaxTree::TopConstRef < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Const] the constant being referenced
  sig { returns(SyntaxTree::Const) }
  attr_reader :constant

  sig do
    params(constant: SyntaxTree::Const, location: SyntaxTree::Location).void
  end
  def initialize(constant:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Unary represents a unary method being called on an expression, as in +!+ or
# +~+.
#
#     !value
#
class SyntaxTree::Unary < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [String] the operator being used
  sig { returns(String) }
  attr_reader :operator

  # [Node] the statement on which to operate
  sig { returns(SyntaxTree::Node) }
  attr_reader :statement

  sig do
    params(
      operator: String,
      statement: SyntaxTree::Node,
      location: SyntaxTree::Location
    ).void
  end
  def initialize(operator:, statement:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Undef represents the use of the +undef+ keyword.
#
#     undef method
#
class SyntaxTree::Undef < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Array[ DynaSymbol | SymbolLiteral ]] the symbols to undefine
  sig do
    returns(T::Array[T.any(SyntaxTree::DynaSymbol, SyntaxTree::SymbolLiteral)])
  end
  attr_reader :symbols

  sig do
    params(
      symbols:
        T::Array[T.any(SyntaxTree::DynaSymbol, SyntaxTree::SymbolLiteral)],
      location: SyntaxTree::Location
    ).void
  end
  def initialize(symbols:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Unless represents the first clause in an +unless+ chain.
#
#     unless predicate
#     end
#
class SyntaxTree::UnlessNode < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [nil | Elsif | Else] the next clause in the chain
  sig { returns(T.nilable(T.any(SyntaxTree::Elsif, SyntaxTree::Else))) }
  attr_reader :consequent

  # [Node] the expression to be checked
  sig { returns(SyntaxTree::Node) }
  attr_reader :predicate

  # [Statements] the expressions to be executed
  sig { returns(SyntaxTree::Statements) }
  attr_reader :statements

  sig do
    params(
      predicate: SyntaxTree::Node,
      statements: SyntaxTree::Statements,
      consequent: T.nilable(T.any(SyntaxTree::Elsif, SyntaxTree::Else)),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(predicate:, statements:, consequent:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Until represents an +until+ loop.
#
#     until predicate
#     end
#
class SyntaxTree::UntilNode < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Node] the expression to be checked
  sig { returns(SyntaxTree::Node) }
  attr_reader :predicate

  # [Statements] the expressions to be executed
  sig { returns(SyntaxTree::Statements) }
  attr_reader :statements

  sig do
    params(
      predicate: SyntaxTree::Node,
      statements: SyntaxTree::Statements,
      location: SyntaxTree::Location
    ).void
  end
  def initialize(predicate:, statements:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# VCall represent any plain named object with Ruby that could be either a
# local variable or a method call.
#
#     variable
#
class SyntaxTree::VCall < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Ident] the value of this expression
  sig { returns(SyntaxTree::Ident) }
  attr_reader :value

  sig { params(value: SyntaxTree::Ident, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# VarField represents a variable that is being assigned a value. As such, it
# is always a child of an assignment type node.
#
#     variable = value
#
# In the example above, the VarField node represents the +variable+ token.
class SyntaxTree::VarField < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [nil | :nil | Const | CVar | GVar | Ident | IVar] the target of this node
  sig do
    returns(
      T.nilable(
        T.any(
          Symbol,
          SyntaxTree::Const,
          SyntaxTree::CVar,
          SyntaxTree::GVar,
          SyntaxTree::Ident,
          SyntaxTree::IVar
        )
      )
    )
  end
  attr_reader :value

  sig do
    params(
      value:
        T.nilable(
          T.any(
            Symbol,
            SyntaxTree::Const,
            SyntaxTree::CVar,
            SyntaxTree::GVar,
            SyntaxTree::Ident,
            SyntaxTree::IVar
          )
        ),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# VarRef represents a variable reference.
#
#     true
#
# This can be a plain local variable like the example above. It can also be a
# constant, a class variable, a global variable, an instance variable, a
# keyword (like +self+, +nil+, +true+, or +false+), or a numbered block
# variable.
class SyntaxTree::VarRef < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Const | CVar | GVar | Ident | IVar | Kw] the value of this node
  sig do
    returns(
      T.any(
        SyntaxTree::Const,
        SyntaxTree::CVar,
        SyntaxTree::GVar,
        SyntaxTree::Ident,
        SyntaxTree::IVar,
        SyntaxTree::Kw
      )
    )
  end
  attr_reader :value

  sig do
    params(
      value:
        T.any(
          SyntaxTree::Const,
          SyntaxTree::CVar,
          SyntaxTree::GVar,
          SyntaxTree::Ident,
          SyntaxTree::IVar,
          SyntaxTree::Kw
        ),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# VoidStmt represents an empty lexical block of code.
#
#     ;;
#
class SyntaxTree::VoidStmt < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  sig { params(location: SyntaxTree::Location).void }
  def initialize(location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# When represents a +when+ clause in a +case+ chain.
#
#     case value
#     when predicate
#     end
#
class SyntaxTree::When < SyntaxTree::Node
  # [Args] the arguments to the when clause
  sig { returns(SyntaxTree::Args) }
  attr_reader :arguments

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [nil | Else | When] the next clause in the chain
  sig { returns(T.nilable(T.any(SyntaxTree::Else, SyntaxTree::When))) }
  attr_reader :consequent

  # [Statements] the expressions to be executed
  sig { returns(SyntaxTree::Statements) }
  attr_reader :statements

  sig do
    params(
      arguments: SyntaxTree::Args,
      statements: SyntaxTree::Statements,
      consequent: T.nilable(T.any(SyntaxTree::Else, SyntaxTree::When)),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(arguments:, statements:, consequent:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# While represents a +while+ loop.
#
#     while predicate
#     end
#
class SyntaxTree::WhileNode < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Node] the expression to be checked
  sig { returns(SyntaxTree::Node) }
  attr_reader :predicate

  # [Statements] the expressions to be executed
  sig { returns(SyntaxTree::Statements) }
  attr_reader :statements

  sig do
    params(
      predicate: SyntaxTree::Node,
      statements: SyntaxTree::Statements,
      location: SyntaxTree::Location
    ).void
  end
  def initialize(predicate:, statements:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Word represents an element within a special array literal that accepts
# interpolation.
#
#     %W[a#{b}c xyz]
#
# In the example above, there would be two Word nodes within a parent Words
# node.
class SyntaxTree::Word < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Array[ StringEmbExpr | StringDVar | TStringContent ]] the parts of the
  # word
  sig do
    returns(
      T::Array[
        T.any(
          SyntaxTree::StringEmbExpr,
          SyntaxTree::StringDVar,
          SyntaxTree::TStringContent
        )
      ]
    )
  end
  attr_reader :parts

  sig do
    params(
      parts:
        T::Array[
          T.any(
            SyntaxTree::StringEmbExpr,
            SyntaxTree::StringDVar,
            SyntaxTree::TStringContent
          )
        ],
      location: SyntaxTree::Location
    ).void
  end
  def initialize(parts:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Words represents a string literal array with interpolation.
#
#     %W[one two three]
#
class SyntaxTree::Words < SyntaxTree::Node
  # [WordsBeg] the token that opens this array literal
  sig { returns(SyntaxTree::WordsBeg) }
  attr_reader :beginning

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Array[ Word ]] the elements of this array
  sig { returns(T::Array[SyntaxTree::Word]) }
  attr_reader :elements

  sig do
    params(
      beginning: SyntaxTree::WordsBeg,
      elements: T::Array[SyntaxTree::Word],
      location: SyntaxTree::Location
    ).void
  end
  def initialize(beginning:, elements:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# WordsBeg represents the beginning of a string literal array with
# interpolation.
#
#     %W[one two three]
#
# In the snippet above, a WordsBeg would be created with the value of "%W[".
# Note that these kinds of arrays can start with a lot of different delimiter
# types (e.g., %W| or %W<).
class SyntaxTree::WordsBeg < SyntaxTree::Node
  # [String] the start of the word literal array
  sig { returns(String) }
  attr_reader :value

  sig { params(value: String, location: SyntaxTree::Location).void }
  def initialize(value:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# XString represents the contents of an XStringLiteral.
#
#     `ls`
#
class SyntaxTree::XString < SyntaxTree::Node
  # [Array[ StringEmbExpr | StringDVar | TStringContent ]] the parts of the
  # xstring
  sig do
    returns(
      T::Array[
        T.any(
          SyntaxTree::StringEmbExpr,
          SyntaxTree::StringDVar,
          SyntaxTree::TStringContent
        )
      ]
    )
  end
  attr_reader :parts

  sig do
    params(
      parts:
        T::Array[
          T.any(
            SyntaxTree::StringEmbExpr,
            SyntaxTree::StringDVar,
            SyntaxTree::TStringContent
          )
        ],
      location: SyntaxTree::Location
    ).void
  end
  def initialize(parts:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# XStringLiteral represents a string that gets executed.
#
#     `ls`
#
class SyntaxTree::XStringLiteral < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  # [Array[ StringEmbExpr | StringDVar | TStringContent ]] the parts of the
  # xstring
  sig do
    returns(
      T::Array[
        T.any(
          SyntaxTree::StringEmbExpr,
          SyntaxTree::StringDVar,
          SyntaxTree::TStringContent
        )
      ]
    )
  end
  attr_reader :parts

  sig do
    params(
      parts:
        T::Array[
          T.any(
            SyntaxTree::StringEmbExpr,
            SyntaxTree::StringDVar,
            SyntaxTree::TStringContent
          )
        ],
      location: SyntaxTree::Location
    ).void
  end
  def initialize(parts:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# Yield represents using the +yield+ keyword with arguments.
#
#     yield value
#
class SyntaxTree::YieldNode < SyntaxTree::Node
  # [nil | Args | Paren] the arguments passed to the yield
  sig { returns(T.nilable(T.any(SyntaxTree::Args, SyntaxTree::Paren))) }
  attr_reader :arguments

  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  sig do
    params(
      arguments: T.nilable(T.any(SyntaxTree::Args, SyntaxTree::Paren)),
      location: SyntaxTree::Location
    ).void
  end
  def initialize(arguments:, location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

# ZSuper represents the bare +super+ keyword with no arguments.
#
#     super
#
class SyntaxTree::ZSuper < SyntaxTree::Node
  # [Array[ Comment | EmbDoc ]] the comments attached to this node
  sig { returns(T::Array[T.any(SyntaxTree::Comment, SyntaxTree::EmbDoc)]) }
  attr_reader :comments

  sig { params(location: SyntaxTree::Location).void }
  def initialize(location:)
  end

  sig { params(visitor: SyntaxTree::BasicVisitor).returns(T.untyped) }
  def accept(visitor)
  end

  sig { returns(T::Array[T.nilable(SyntaxTree::Node)]) }
  def child_nodes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
  end
end

class SyntaxTree::BasicVisitor
  sig { overridable.params(node: SyntaxTree::BEGINBlock).returns(T.untyped) }
  def visit_BEGIN(node)
  end

  sig { overridable.params(node: SyntaxTree::CHAR).returns(T.untyped) }
  def visit_CHAR(node)
  end

  sig { overridable.params(node: SyntaxTree::ENDBlock).returns(T.untyped) }
  def visit_END(node)
  end

  sig { overridable.params(node: SyntaxTree::EndContent).returns(T.untyped) }
  def visit___end__(node)
  end

  sig { overridable.params(node: SyntaxTree::AliasNode).returns(T.untyped) }
  def visit_alias(node)
  end

  sig { overridable.params(node: SyntaxTree::ARef).returns(T.untyped) }
  def visit_aref(node)
  end

  sig { overridable.params(node: SyntaxTree::ARefField).returns(T.untyped) }
  def visit_aref_field(node)
  end

  sig { overridable.params(node: SyntaxTree::ArgParen).returns(T.untyped) }
  def visit_arg_paren(node)
  end

  sig { overridable.params(node: SyntaxTree::Args).returns(T.untyped) }
  def visit_args(node)
  end

  sig { overridable.params(node: SyntaxTree::ArgBlock).returns(T.untyped) }
  def visit_arg_block(node)
  end

  sig { overridable.params(node: SyntaxTree::ArgStar).returns(T.untyped) }
  def visit_arg_star(node)
  end

  sig { overridable.params(node: SyntaxTree::ArgsForward).returns(T.untyped) }
  def visit_args_forward(node)
  end

  sig { overridable.params(node: SyntaxTree::ArrayLiteral).returns(T.untyped) }
  def visit_array(node)
  end

  sig { overridable.params(node: SyntaxTree::AryPtn).returns(T.untyped) }
  def visit_aryptn(node)
  end

  sig { overridable.params(node: SyntaxTree::Assign).returns(T.untyped) }
  def visit_assign(node)
  end

  sig { overridable.params(node: SyntaxTree::Assoc).returns(T.untyped) }
  def visit_assoc(node)
  end

  sig { overridable.params(node: SyntaxTree::AssocSplat).returns(T.untyped) }
  def visit_assoc_splat(node)
  end

  sig { overridable.params(node: SyntaxTree::Backref).returns(T.untyped) }
  def visit_backref(node)
  end

  sig { overridable.params(node: SyntaxTree::Backtick).returns(T.untyped) }
  def visit_backtick(node)
  end

  sig { overridable.params(node: SyntaxTree::BareAssocHash).returns(T.untyped) }
  def visit_bare_assoc_hash(node)
  end

  sig { overridable.params(node: SyntaxTree::Begin).returns(T.untyped) }
  def visit_begin(node)
  end

  sig { overridable.params(node: SyntaxTree::PinnedBegin).returns(T.untyped) }
  def visit_pinned_begin(node)
  end

  sig { overridable.params(node: SyntaxTree::Binary).returns(T.untyped) }
  def visit_binary(node)
  end

  sig { overridable.params(node: SyntaxTree::BlockVar).returns(T.untyped) }
  def visit_block_var(node)
  end

  sig { overridable.params(node: SyntaxTree::BlockArg).returns(T.untyped) }
  def visit_blockarg(node)
  end

  sig { overridable.params(node: SyntaxTree::BodyStmt).returns(T.untyped) }
  def visit_bodystmt(node)
  end

  sig { overridable.params(node: SyntaxTree::Break).returns(T.untyped) }
  def visit_break(node)
  end

  sig { overridable.params(node: SyntaxTree::CallNode).returns(T.untyped) }
  def visit_call(node)
  end

  sig { overridable.params(node: SyntaxTree::Case).returns(T.untyped) }
  def visit_case(node)
  end

  sig { overridable.params(node: SyntaxTree::RAssign).returns(T.untyped) }
  def visit_rassign(node)
  end

  sig do
    overridable.params(node: SyntaxTree::ClassDeclaration).returns(T.untyped)
  end
  def visit_class(node)
  end

  sig { overridable.params(node: SyntaxTree::Comma).returns(T.untyped) }
  def visit_comma(node)
  end

  sig { overridable.params(node: SyntaxTree::Command).returns(T.untyped) }
  def visit_command(node)
  end

  sig { overridable.params(node: SyntaxTree::CommandCall).returns(T.untyped) }
  def visit_command_call(node)
  end

  sig { overridable.params(node: SyntaxTree::Comment).returns(T.untyped) }
  def visit_comment(node)
  end

  sig { overridable.params(node: SyntaxTree::Const).returns(T.untyped) }
  def visit_const(node)
  end

  sig do
    overridable.params(node: SyntaxTree::ConstPathField).returns(T.untyped)
  end
  def visit_const_path_field(node)
  end

  sig { overridable.params(node: SyntaxTree::ConstPathRef).returns(T.untyped) }
  def visit_const_path_ref(node)
  end

  sig { overridable.params(node: SyntaxTree::ConstRef).returns(T.untyped) }
  def visit_const_ref(node)
  end

  sig { overridable.params(node: SyntaxTree::CVar).returns(T.untyped) }
  def visit_cvar(node)
  end

  sig { overridable.params(node: SyntaxTree::DefNode).returns(T.untyped) }
  def visit_def(node)
  end

  sig { overridable.params(node: SyntaxTree::Defined).returns(T.untyped) }
  def visit_defined(node)
  end

  sig { overridable.params(node: SyntaxTree::BlockNode).returns(T.untyped) }
  def visit_block(node)
  end

  sig { overridable.params(node: SyntaxTree::RangeNode).returns(T.untyped) }
  def visit_range(node)
  end

  sig { overridable.params(node: SyntaxTree::DynaSymbol).returns(T.untyped) }
  def visit_dyna_symbol(node)
  end

  sig { overridable.params(node: SyntaxTree::Else).returns(T.untyped) }
  def visit_else(node)
  end

  sig { overridable.params(node: SyntaxTree::Elsif).returns(T.untyped) }
  def visit_elsif(node)
  end

  sig { overridable.params(node: SyntaxTree::EmbDoc).returns(T.untyped) }
  def visit_embdoc(node)
  end

  sig { overridable.params(node: SyntaxTree::EmbExprBeg).returns(T.untyped) }
  def visit_embexpr_beg(node)
  end

  sig { overridable.params(node: SyntaxTree::EmbExprEnd).returns(T.untyped) }
  def visit_embexpr_end(node)
  end

  sig { overridable.params(node: SyntaxTree::EmbVar).returns(T.untyped) }
  def visit_embvar(node)
  end

  sig { overridable.params(node: SyntaxTree::Ensure).returns(T.untyped) }
  def visit_ensure(node)
  end

  sig { overridable.params(node: SyntaxTree::ExcessedComma).returns(T.untyped) }
  def visit_excessed_comma(node)
  end

  sig { overridable.params(node: SyntaxTree::Field).returns(T.untyped) }
  def visit_field(node)
  end

  sig { overridable.params(node: SyntaxTree::FloatLiteral).returns(T.untyped) }
  def visit_float(node)
  end

  sig { overridable.params(node: SyntaxTree::FndPtn).returns(T.untyped) }
  def visit_fndptn(node)
  end

  sig { overridable.params(node: SyntaxTree::For).returns(T.untyped) }
  def visit_for(node)
  end

  sig { overridable.params(node: SyntaxTree::GVar).returns(T.untyped) }
  def visit_gvar(node)
  end

  sig { overridable.params(node: SyntaxTree::HashLiteral).returns(T.untyped) }
  def visit_hash(node)
  end

  sig { overridable.params(node: SyntaxTree::Heredoc).returns(T.untyped) }
  def visit_heredoc(node)
  end

  sig { overridable.params(node: SyntaxTree::HeredocBeg).returns(T.untyped) }
  def visit_heredoc_beg(node)
  end

  sig { overridable.params(node: SyntaxTree::HeredocEnd).returns(T.untyped) }
  def visit_heredoc_end(node)
  end

  sig { overridable.params(node: SyntaxTree::HshPtn).returns(T.untyped) }
  def visit_hshptn(node)
  end

  sig { overridable.params(node: SyntaxTree::Ident).returns(T.untyped) }
  def visit_ident(node)
  end

  sig { overridable.params(node: SyntaxTree::IfNode).returns(T.untyped) }
  def visit_if(node)
  end

  sig { overridable.params(node: SyntaxTree::IfOp).returns(T.untyped) }
  def visit_if_op(node)
  end

  sig { overridable.params(node: SyntaxTree::Imaginary).returns(T.untyped) }
  def visit_imaginary(node)
  end

  sig { overridable.params(node: SyntaxTree::In).returns(T.untyped) }
  def visit_in(node)
  end

  sig { overridable.params(node: SyntaxTree::Int).returns(T.untyped) }
  def visit_int(node)
  end

  sig { overridable.params(node: SyntaxTree::IVar).returns(T.untyped) }
  def visit_ivar(node)
  end

  sig { overridable.params(node: SyntaxTree::Kw).returns(T.untyped) }
  def visit_kw(node)
  end

  sig { overridable.params(node: SyntaxTree::KwRestParam).returns(T.untyped) }
  def visit_kwrest_param(node)
  end

  sig { overridable.params(node: SyntaxTree::Label).returns(T.untyped) }
  def visit_label(node)
  end

  sig { overridable.params(node: SyntaxTree::LabelEnd).returns(T.untyped) }
  def visit_label_end(node)
  end

  sig { overridable.params(node: SyntaxTree::Lambda).returns(T.untyped) }
  def visit_lambda(node)
  end

  sig { overridable.params(node: SyntaxTree::LambdaVar).returns(T.untyped) }
  def visit_lambda_var(node)
  end

  sig { overridable.params(node: SyntaxTree::LBrace).returns(T.untyped) }
  def visit_lbrace(node)
  end

  sig { overridable.params(node: SyntaxTree::LBracket).returns(T.untyped) }
  def visit_lbracket(node)
  end

  sig { overridable.params(node: SyntaxTree::LParen).returns(T.untyped) }
  def visit_lparen(node)
  end

  sig { overridable.params(node: SyntaxTree::MAssign).returns(T.untyped) }
  def visit_massign(node)
  end

  sig do
    overridable.params(node: SyntaxTree::MethodAddBlock).returns(T.untyped)
  end
  def visit_method_add_block(node)
  end

  sig { overridable.params(node: SyntaxTree::MLHS).returns(T.untyped) }
  def visit_mlhs(node)
  end

  sig { overridable.params(node: SyntaxTree::MLHSParen).returns(T.untyped) }
  def visit_mlhs_paren(node)
  end

  sig do
    overridable.params(node: SyntaxTree::ModuleDeclaration).returns(T.untyped)
  end
  def visit_module(node)
  end

  sig { overridable.params(node: SyntaxTree::MRHS).returns(T.untyped) }
  def visit_mrhs(node)
  end

  sig { overridable.params(node: SyntaxTree::Next).returns(T.untyped) }
  def visit_next(node)
  end

  sig { overridable.params(node: SyntaxTree::Op).returns(T.untyped) }
  def visit_op(node)
  end

  sig { overridable.params(node: SyntaxTree::OpAssign).returns(T.untyped) }
  def visit_opassign(node)
  end

  sig { overridable.params(node: SyntaxTree::Params).returns(T.untyped) }
  def visit_params(node)
  end

  sig { overridable.params(node: SyntaxTree::Paren).returns(T.untyped) }
  def visit_paren(node)
  end

  sig { overridable.params(node: SyntaxTree::Period).returns(T.untyped) }
  def visit_period(node)
  end

  sig { overridable.params(node: SyntaxTree::Program).returns(T.untyped) }
  def visit_program(node)
  end

  sig { overridable.params(node: SyntaxTree::QSymbols).returns(T.untyped) }
  def visit_qsymbols(node)
  end

  sig { overridable.params(node: SyntaxTree::QSymbolsBeg).returns(T.untyped) }
  def visit_qsymbols_beg(node)
  end

  sig { overridable.params(node: SyntaxTree::QWords).returns(T.untyped) }
  def visit_qwords(node)
  end

  sig { overridable.params(node: SyntaxTree::QWordsBeg).returns(T.untyped) }
  def visit_qwords_beg(node)
  end

  sig do
    overridable.params(node: SyntaxTree::RationalLiteral).returns(T.untyped)
  end
  def visit_rational(node)
  end

  sig { overridable.params(node: SyntaxTree::RBrace).returns(T.untyped) }
  def visit_rbrace(node)
  end

  sig { overridable.params(node: SyntaxTree::RBracket).returns(T.untyped) }
  def visit_rbracket(node)
  end

  sig { overridable.params(node: SyntaxTree::Redo).returns(T.untyped) }
  def visit_redo(node)
  end

  sig { overridable.params(node: SyntaxTree::RegexpContent).returns(T.untyped) }
  def visit_regexp_content(node)
  end

  sig { overridable.params(node: SyntaxTree::RegexpBeg).returns(T.untyped) }
  def visit_regexp_beg(node)
  end

  sig { overridable.params(node: SyntaxTree::RegexpEnd).returns(T.untyped) }
  def visit_regexp_end(node)
  end

  sig { overridable.params(node: SyntaxTree::RegexpLiteral).returns(T.untyped) }
  def visit_regexp_literal(node)
  end

  sig { overridable.params(node: SyntaxTree::RescueEx).returns(T.untyped) }
  def visit_rescue_ex(node)
  end

  sig { overridable.params(node: SyntaxTree::Rescue).returns(T.untyped) }
  def visit_rescue(node)
  end

  sig { overridable.params(node: SyntaxTree::RescueMod).returns(T.untyped) }
  def visit_rescue_mod(node)
  end

  sig { overridable.params(node: SyntaxTree::RestParam).returns(T.untyped) }
  def visit_rest_param(node)
  end

  sig { overridable.params(node: SyntaxTree::Retry).returns(T.untyped) }
  def visit_retry(node)
  end

  sig { overridable.params(node: SyntaxTree::ReturnNode).returns(T.untyped) }
  def visit_return(node)
  end

  sig { overridable.params(node: SyntaxTree::RParen).returns(T.untyped) }
  def visit_rparen(node)
  end

  sig { overridable.params(node: SyntaxTree::SClass).returns(T.untyped) }
  def visit_sclass(node)
  end

  sig { overridable.params(node: SyntaxTree::Statements).returns(T.untyped) }
  def visit_statements(node)
  end

  sig { overridable.params(node: SyntaxTree::StringContent).returns(T.untyped) }
  def visit_string_content(node)
  end

  sig { overridable.params(node: SyntaxTree::StringConcat).returns(T.untyped) }
  def visit_string_concat(node)
  end

  sig { overridable.params(node: SyntaxTree::StringDVar).returns(T.untyped) }
  def visit_string_dvar(node)
  end

  sig { overridable.params(node: SyntaxTree::StringEmbExpr).returns(T.untyped) }
  def visit_string_embexpr(node)
  end

  sig { overridable.params(node: SyntaxTree::StringLiteral).returns(T.untyped) }
  def visit_string_literal(node)
  end

  sig { overridable.params(node: SyntaxTree::Super).returns(T.untyped) }
  def visit_super(node)
  end

  sig { overridable.params(node: SyntaxTree::SymBeg).returns(T.untyped) }
  def visit_symbeg(node)
  end

  sig { overridable.params(node: SyntaxTree::SymbolContent).returns(T.untyped) }
  def visit_symbol_content(node)
  end

  sig { overridable.params(node: SyntaxTree::SymbolLiteral).returns(T.untyped) }
  def visit_symbol_literal(node)
  end

  sig { overridable.params(node: SyntaxTree::Symbols).returns(T.untyped) }
  def visit_symbols(node)
  end

  sig { overridable.params(node: SyntaxTree::SymbolsBeg).returns(T.untyped) }
  def visit_symbols_beg(node)
  end

  sig { overridable.params(node: SyntaxTree::TLambda).returns(T.untyped) }
  def visit_tlambda(node)
  end

  sig { overridable.params(node: SyntaxTree::TLamBeg).returns(T.untyped) }
  def visit_tlambeg(node)
  end

  sig { overridable.params(node: SyntaxTree::TopConstField).returns(T.untyped) }
  def visit_top_const_field(node)
  end

  sig { overridable.params(node: SyntaxTree::TopConstRef).returns(T.untyped) }
  def visit_top_const_ref(node)
  end

  sig { overridable.params(node: SyntaxTree::TStringBeg).returns(T.untyped) }
  def visit_tstring_beg(node)
  end

  sig do
    overridable.params(node: SyntaxTree::TStringContent).returns(T.untyped)
  end
  def visit_tstring_content(node)
  end

  sig { overridable.params(node: SyntaxTree::TStringEnd).returns(T.untyped) }
  def visit_tstring_end(node)
  end

  sig { overridable.params(node: SyntaxTree::Not).returns(T.untyped) }
  def visit_not(node)
  end

  sig { overridable.params(node: SyntaxTree::Unary).returns(T.untyped) }
  def visit_unary(node)
  end

  sig { overridable.params(node: SyntaxTree::Undef).returns(T.untyped) }
  def visit_undef(node)
  end

  sig { overridable.params(node: SyntaxTree::UnlessNode).returns(T.untyped) }
  def visit_unless(node)
  end

  sig { overridable.params(node: SyntaxTree::UntilNode).returns(T.untyped) }
  def visit_until(node)
  end

  sig { overridable.params(node: SyntaxTree::VarField).returns(T.untyped) }
  def visit_var_field(node)
  end

  sig { overridable.params(node: SyntaxTree::VarRef).returns(T.untyped) }
  def visit_var_ref(node)
  end

  sig { overridable.params(node: SyntaxTree::PinnedVarRef).returns(T.untyped) }
  def visit_pinned_var_ref(node)
  end

  sig { overridable.params(node: SyntaxTree::VCall).returns(T.untyped) }
  def visit_vcall(node)
  end

  sig { overridable.params(node: SyntaxTree::VoidStmt).returns(T.untyped) }
  def visit_void_stmt(node)
  end

  sig { overridable.params(node: SyntaxTree::When).returns(T.untyped) }
  def visit_when(node)
  end

  sig { overridable.params(node: SyntaxTree::WhileNode).returns(T.untyped) }
  def visit_while(node)
  end

  sig { overridable.params(node: SyntaxTree::Word).returns(T.untyped) }
  def visit_word(node)
  end

  sig { overridable.params(node: SyntaxTree::Words).returns(T.untyped) }
  def visit_words(node)
  end

  sig { overridable.params(node: SyntaxTree::WordsBeg).returns(T.untyped) }
  def visit_words_beg(node)
  end

  sig { overridable.params(node: SyntaxTree::XString).returns(T.untyped) }
  def visit_xstring(node)
  end

  sig do
    overridable.params(node: SyntaxTree::XStringLiteral).returns(T.untyped)
  end
  def visit_xstring_literal(node)
  end

  sig { overridable.params(node: SyntaxTree::YieldNode).returns(T.untyped) }
  def visit_yield(node)
  end

  sig { overridable.params(node: SyntaxTree::ZSuper).returns(T.untyped) }
  def visit_zsuper(node)
  end
end

class SyntaxTree::Visitor < SyntaxTree::BasicVisitor
  sig { override.params(node: SyntaxTree::BEGINBlock).returns(T.untyped) }
  def visit_BEGIN(node)
  end

  sig { override.params(node: SyntaxTree::CHAR).returns(T.untyped) }
  def visit_CHAR(node)
  end

  sig { override.params(node: SyntaxTree::ENDBlock).returns(T.untyped) }
  def visit_END(node)
  end

  sig { override.params(node: SyntaxTree::EndContent).returns(T.untyped) }
  def visit___end__(node)
  end

  sig { override.params(node: SyntaxTree::AliasNode).returns(T.untyped) }
  def visit_alias(node)
  end

  sig { override.params(node: SyntaxTree::ARef).returns(T.untyped) }
  def visit_aref(node)
  end

  sig { override.params(node: SyntaxTree::ARefField).returns(T.untyped) }
  def visit_aref_field(node)
  end

  sig { override.params(node: SyntaxTree::ArgParen).returns(T.untyped) }
  def visit_arg_paren(node)
  end

  sig { override.params(node: SyntaxTree::Args).returns(T.untyped) }
  def visit_args(node)
  end

  sig { override.params(node: SyntaxTree::ArgBlock).returns(T.untyped) }
  def visit_arg_block(node)
  end

  sig { override.params(node: SyntaxTree::ArgStar).returns(T.untyped) }
  def visit_arg_star(node)
  end

  sig { override.params(node: SyntaxTree::ArgsForward).returns(T.untyped) }
  def visit_args_forward(node)
  end

  sig { override.params(node: SyntaxTree::ArrayLiteral).returns(T.untyped) }
  def visit_array(node)
  end

  sig { override.params(node: SyntaxTree::AryPtn).returns(T.untyped) }
  def visit_aryptn(node)
  end

  sig { override.params(node: SyntaxTree::Assign).returns(T.untyped) }
  def visit_assign(node)
  end

  sig { override.params(node: SyntaxTree::Assoc).returns(T.untyped) }
  def visit_assoc(node)
  end

  sig { override.params(node: SyntaxTree::AssocSplat).returns(T.untyped) }
  def visit_assoc_splat(node)
  end

  sig { override.params(node: SyntaxTree::Backref).returns(T.untyped) }
  def visit_backref(node)
  end

  sig { override.params(node: SyntaxTree::Backtick).returns(T.untyped) }
  def visit_backtick(node)
  end

  sig { override.params(node: SyntaxTree::BareAssocHash).returns(T.untyped) }
  def visit_bare_assoc_hash(node)
  end

  sig { override.params(node: SyntaxTree::Begin).returns(T.untyped) }
  def visit_begin(node)
  end

  sig { override.params(node: SyntaxTree::PinnedBegin).returns(T.untyped) }
  def visit_pinned_begin(node)
  end

  sig { override.params(node: SyntaxTree::Binary).returns(T.untyped) }
  def visit_binary(node)
  end

  sig { override.params(node: SyntaxTree::BlockVar).returns(T.untyped) }
  def visit_block_var(node)
  end

  sig { override.params(node: SyntaxTree::BlockArg).returns(T.untyped) }
  def visit_blockarg(node)
  end

  sig { override.params(node: SyntaxTree::BodyStmt).returns(T.untyped) }
  def visit_bodystmt(node)
  end

  sig { override.params(node: SyntaxTree::Break).returns(T.untyped) }
  def visit_break(node)
  end

  sig { override.params(node: SyntaxTree::CallNode).returns(T.untyped) }
  def visit_call(node)
  end

  sig { override.params(node: SyntaxTree::Case).returns(T.untyped) }
  def visit_case(node)
  end

  sig { override.params(node: SyntaxTree::RAssign).returns(T.untyped) }
  def visit_rassign(node)
  end

  sig { override.params(node: SyntaxTree::ClassDeclaration).returns(T.untyped) }
  def visit_class(node)
  end

  sig { override.params(node: SyntaxTree::Comma).returns(T.untyped) }
  def visit_comma(node)
  end

  sig { override.params(node: SyntaxTree::Command).returns(T.untyped) }
  def visit_command(node)
  end

  sig { override.params(node: SyntaxTree::CommandCall).returns(T.untyped) }
  def visit_command_call(node)
  end

  sig { override.params(node: SyntaxTree::Comment).returns(T.untyped) }
  def visit_comment(node)
  end

  sig { override.params(node: SyntaxTree::Const).returns(T.untyped) }
  def visit_const(node)
  end

  sig { override.params(node: SyntaxTree::ConstPathField).returns(T.untyped) }
  def visit_const_path_field(node)
  end

  sig { override.params(node: SyntaxTree::ConstPathRef).returns(T.untyped) }
  def visit_const_path_ref(node)
  end

  sig { override.params(node: SyntaxTree::ConstRef).returns(T.untyped) }
  def visit_const_ref(node)
  end

  sig { override.params(node: SyntaxTree::CVar).returns(T.untyped) }
  def visit_cvar(node)
  end

  sig { override.params(node: SyntaxTree::DefNode).returns(T.untyped) }
  def visit_def(node)
  end

  sig { override.params(node: SyntaxTree::Defined).returns(T.untyped) }
  def visit_defined(node)
  end

  sig { override.params(node: SyntaxTree::BlockNode).returns(T.untyped) }
  def visit_block(node)
  end

  sig { override.params(node: SyntaxTree::RangeNode).returns(T.untyped) }
  def visit_range(node)
  end

  sig { override.params(node: SyntaxTree::DynaSymbol).returns(T.untyped) }
  def visit_dyna_symbol(node)
  end

  sig { override.params(node: SyntaxTree::Else).returns(T.untyped) }
  def visit_else(node)
  end

  sig { override.params(node: SyntaxTree::Elsif).returns(T.untyped) }
  def visit_elsif(node)
  end

  sig { override.params(node: SyntaxTree::EmbDoc).returns(T.untyped) }
  def visit_embdoc(node)
  end

  sig { override.params(node: SyntaxTree::EmbExprBeg).returns(T.untyped) }
  def visit_embexpr_beg(node)
  end

  sig { override.params(node: SyntaxTree::EmbExprEnd).returns(T.untyped) }
  def visit_embexpr_end(node)
  end

  sig { override.params(node: SyntaxTree::EmbVar).returns(T.untyped) }
  def visit_embvar(node)
  end

  sig { override.params(node: SyntaxTree::Ensure).returns(T.untyped) }
  def visit_ensure(node)
  end

  sig { override.params(node: SyntaxTree::ExcessedComma).returns(T.untyped) }
  def visit_excessed_comma(node)
  end

  sig { override.params(node: SyntaxTree::Field).returns(T.untyped) }
  def visit_field(node)
  end

  sig { override.params(node: SyntaxTree::FloatLiteral).returns(T.untyped) }
  def visit_float(node)
  end

  sig { override.params(node: SyntaxTree::FndPtn).returns(T.untyped) }
  def visit_fndptn(node)
  end

  sig { override.params(node: SyntaxTree::For).returns(T.untyped) }
  def visit_for(node)
  end

  sig { override.params(node: SyntaxTree::GVar).returns(T.untyped) }
  def visit_gvar(node)
  end

  sig { override.params(node: SyntaxTree::HashLiteral).returns(T.untyped) }
  def visit_hash(node)
  end

  sig { override.params(node: SyntaxTree::Heredoc).returns(T.untyped) }
  def visit_heredoc(node)
  end

  sig { override.params(node: SyntaxTree::HeredocBeg).returns(T.untyped) }
  def visit_heredoc_beg(node)
  end

  sig { override.params(node: SyntaxTree::HeredocEnd).returns(T.untyped) }
  def visit_heredoc_end(node)
  end

  sig { override.params(node: SyntaxTree::HshPtn).returns(T.untyped) }
  def visit_hshptn(node)
  end

  sig { override.params(node: SyntaxTree::Ident).returns(T.untyped) }
  def visit_ident(node)
  end

  sig { override.params(node: SyntaxTree::IfNode).returns(T.untyped) }
  def visit_if(node)
  end

  sig { override.params(node: SyntaxTree::IfOp).returns(T.untyped) }
  def visit_if_op(node)
  end

  sig { override.params(node: SyntaxTree::Imaginary).returns(T.untyped) }
  def visit_imaginary(node)
  end

  sig { override.params(node: SyntaxTree::In).returns(T.untyped) }
  def visit_in(node)
  end

  sig { override.params(node: SyntaxTree::Int).returns(T.untyped) }
  def visit_int(node)
  end

  sig { override.params(node: SyntaxTree::IVar).returns(T.untyped) }
  def visit_ivar(node)
  end

  sig { override.params(node: SyntaxTree::Kw).returns(T.untyped) }
  def visit_kw(node)
  end

  sig { override.params(node: SyntaxTree::KwRestParam).returns(T.untyped) }
  def visit_kwrest_param(node)
  end

  sig { override.params(node: SyntaxTree::Label).returns(T.untyped) }
  def visit_label(node)
  end

  sig { override.params(node: SyntaxTree::LabelEnd).returns(T.untyped) }
  def visit_label_end(node)
  end

  sig { override.params(node: SyntaxTree::Lambda).returns(T.untyped) }
  def visit_lambda(node)
  end

  sig { override.params(node: SyntaxTree::LambdaVar).returns(T.untyped) }
  def visit_lambda_var(node)
  end

  sig { override.params(node: SyntaxTree::LBrace).returns(T.untyped) }
  def visit_lbrace(node)
  end

  sig { override.params(node: SyntaxTree::LBracket).returns(T.untyped) }
  def visit_lbracket(node)
  end

  sig { override.params(node: SyntaxTree::LParen).returns(T.untyped) }
  def visit_lparen(node)
  end

  sig { override.params(node: SyntaxTree::MAssign).returns(T.untyped) }
  def visit_massign(node)
  end

  sig { override.params(node: SyntaxTree::MethodAddBlock).returns(T.untyped) }
  def visit_method_add_block(node)
  end

  sig { override.params(node: SyntaxTree::MLHS).returns(T.untyped) }
  def visit_mlhs(node)
  end

  sig { override.params(node: SyntaxTree::MLHSParen).returns(T.untyped) }
  def visit_mlhs_paren(node)
  end

  sig do
    override.params(node: SyntaxTree::ModuleDeclaration).returns(T.untyped)
  end
  def visit_module(node)
  end

  sig { override.params(node: SyntaxTree::MRHS).returns(T.untyped) }
  def visit_mrhs(node)
  end

  sig { override.params(node: SyntaxTree::Next).returns(T.untyped) }
  def visit_next(node)
  end

  sig { override.params(node: SyntaxTree::Op).returns(T.untyped) }
  def visit_op(node)
  end

  sig { override.params(node: SyntaxTree::OpAssign).returns(T.untyped) }
  def visit_opassign(node)
  end

  sig { override.params(node: SyntaxTree::Params).returns(T.untyped) }
  def visit_params(node)
  end

  sig { override.params(node: SyntaxTree::Paren).returns(T.untyped) }
  def visit_paren(node)
  end

  sig { override.params(node: SyntaxTree::Period).returns(T.untyped) }
  def visit_period(node)
  end

  sig { override.params(node: SyntaxTree::Program).returns(T.untyped) }
  def visit_program(node)
  end

  sig { override.params(node: SyntaxTree::QSymbols).returns(T.untyped) }
  def visit_qsymbols(node)
  end

  sig { override.params(node: SyntaxTree::QSymbolsBeg).returns(T.untyped) }
  def visit_qsymbols_beg(node)
  end

  sig { override.params(node: SyntaxTree::QWords).returns(T.untyped) }
  def visit_qwords(node)
  end

  sig { override.params(node: SyntaxTree::QWordsBeg).returns(T.untyped) }
  def visit_qwords_beg(node)
  end

  sig { override.params(node: SyntaxTree::RationalLiteral).returns(T.untyped) }
  def visit_rational(node)
  end

  sig { override.params(node: SyntaxTree::RBrace).returns(T.untyped) }
  def visit_rbrace(node)
  end

  sig { override.params(node: SyntaxTree::RBracket).returns(T.untyped) }
  def visit_rbracket(node)
  end

  sig { override.params(node: SyntaxTree::Redo).returns(T.untyped) }
  def visit_redo(node)
  end

  sig { override.params(node: SyntaxTree::RegexpContent).returns(T.untyped) }
  def visit_regexp_content(node)
  end

  sig { override.params(node: SyntaxTree::RegexpBeg).returns(T.untyped) }
  def visit_regexp_beg(node)
  end

  sig { override.params(node: SyntaxTree::RegexpEnd).returns(T.untyped) }
  def visit_regexp_end(node)
  end

  sig { override.params(node: SyntaxTree::RegexpLiteral).returns(T.untyped) }
  def visit_regexp_literal(node)
  end

  sig { override.params(node: SyntaxTree::RescueEx).returns(T.untyped) }
  def visit_rescue_ex(node)
  end

  sig { override.params(node: SyntaxTree::Rescue).returns(T.untyped) }
  def visit_rescue(node)
  end

  sig { override.params(node: SyntaxTree::RescueMod).returns(T.untyped) }
  def visit_rescue_mod(node)
  end

  sig { override.params(node: SyntaxTree::RestParam).returns(T.untyped) }
  def visit_rest_param(node)
  end

  sig { override.params(node: SyntaxTree::Retry).returns(T.untyped) }
  def visit_retry(node)
  end

  sig { override.params(node: SyntaxTree::ReturnNode).returns(T.untyped) }
  def visit_return(node)
  end

  sig { override.params(node: SyntaxTree::RParen).returns(T.untyped) }
  def visit_rparen(node)
  end

  sig { override.params(node: SyntaxTree::SClass).returns(T.untyped) }
  def visit_sclass(node)
  end

  sig { override.params(node: SyntaxTree::Statements).returns(T.untyped) }
  def visit_statements(node)
  end

  sig { override.params(node: SyntaxTree::StringContent).returns(T.untyped) }
  def visit_string_content(node)
  end

  sig { override.params(node: SyntaxTree::StringConcat).returns(T.untyped) }
  def visit_string_concat(node)
  end

  sig { override.params(node: SyntaxTree::StringDVar).returns(T.untyped) }
  def visit_string_dvar(node)
  end

  sig { override.params(node: SyntaxTree::StringEmbExpr).returns(T.untyped) }
  def visit_string_embexpr(node)
  end

  sig { override.params(node: SyntaxTree::StringLiteral).returns(T.untyped) }
  def visit_string_literal(node)
  end

  sig { override.params(node: SyntaxTree::Super).returns(T.untyped) }
  def visit_super(node)
  end

  sig { override.params(node: SyntaxTree::SymBeg).returns(T.untyped) }
  def visit_symbeg(node)
  end

  sig { override.params(node: SyntaxTree::SymbolContent).returns(T.untyped) }
  def visit_symbol_content(node)
  end

  sig { override.params(node: SyntaxTree::SymbolLiteral).returns(T.untyped) }
  def visit_symbol_literal(node)
  end

  sig { override.params(node: SyntaxTree::Symbols).returns(T.untyped) }
  def visit_symbols(node)
  end

  sig { override.params(node: SyntaxTree::SymbolsBeg).returns(T.untyped) }
  def visit_symbols_beg(node)
  end

  sig { override.params(node: SyntaxTree::TLambda).returns(T.untyped) }
  def visit_tlambda(node)
  end

  sig { override.params(node: SyntaxTree::TLamBeg).returns(T.untyped) }
  def visit_tlambeg(node)
  end

  sig { override.params(node: SyntaxTree::TopConstField).returns(T.untyped) }
  def visit_top_const_field(node)
  end

  sig { override.params(node: SyntaxTree::TopConstRef).returns(T.untyped) }
  def visit_top_const_ref(node)
  end

  sig { override.params(node: SyntaxTree::TStringBeg).returns(T.untyped) }
  def visit_tstring_beg(node)
  end

  sig { override.params(node: SyntaxTree::TStringContent).returns(T.untyped) }
  def visit_tstring_content(node)
  end

  sig { override.params(node: SyntaxTree::TStringEnd).returns(T.untyped) }
  def visit_tstring_end(node)
  end

  sig { override.params(node: SyntaxTree::Not).returns(T.untyped) }
  def visit_not(node)
  end

  sig { override.params(node: SyntaxTree::Unary).returns(T.untyped) }
  def visit_unary(node)
  end

  sig { override.params(node: SyntaxTree::Undef).returns(T.untyped) }
  def visit_undef(node)
  end

  sig { override.params(node: SyntaxTree::UnlessNode).returns(T.untyped) }
  def visit_unless(node)
  end

  sig { override.params(node: SyntaxTree::UntilNode).returns(T.untyped) }
  def visit_until(node)
  end

  sig { override.params(node: SyntaxTree::VarField).returns(T.untyped) }
  def visit_var_field(node)
  end

  sig { override.params(node: SyntaxTree::VarRef).returns(T.untyped) }
  def visit_var_ref(node)
  end

  sig { override.params(node: SyntaxTree::PinnedVarRef).returns(T.untyped) }
  def visit_pinned_var_ref(node)
  end

  sig { override.params(node: SyntaxTree::VCall).returns(T.untyped) }
  def visit_vcall(node)
  end

  sig { override.params(node: SyntaxTree::VoidStmt).returns(T.untyped) }
  def visit_void_stmt(node)
  end

  sig { override.params(node: SyntaxTree::When).returns(T.untyped) }
  def visit_when(node)
  end

  sig { override.params(node: SyntaxTree::WhileNode).returns(T.untyped) }
  def visit_while(node)
  end

  sig { override.params(node: SyntaxTree::Word).returns(T.untyped) }
  def visit_word(node)
  end

  sig { override.params(node: SyntaxTree::Words).returns(T.untyped) }
  def visit_words(node)
  end

  sig { override.params(node: SyntaxTree::WordsBeg).returns(T.untyped) }
  def visit_words_beg(node)
  end

  sig { override.params(node: SyntaxTree::XString).returns(T.untyped) }
  def visit_xstring(node)
  end

  sig { override.params(node: SyntaxTree::XStringLiteral).returns(T.untyped) }
  def visit_xstring_literal(node)
  end

  sig { override.params(node: SyntaxTree::YieldNode).returns(T.untyped) }
  def visit_yield(node)
  end

  sig { override.params(node: SyntaxTree::ZSuper).returns(T.untyped) }
  def visit_zsuper(node)
  end
end
