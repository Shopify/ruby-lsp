# typed: true

module YARP
  class << self
    sig { params(source: String).returns(ParseResult) }
    def parse(*source); end
  end

  class ParseResult
    sig { returns(YARP::Node) }
    def value; end

    sig { returns(T::Boolean) }
    def failure?; end

    sig { returns(T::Boolean) }
    def success?; end
  end

  class Node
    sig { returns(T::Array[T.nilable(YARP::Node)]) }
    def child_nodes; end

    sig { returns(Location) }
    def location; end
  end

  class Location
    sig { returns(Integer) }
    def start_offset; end

    sig { returns(Integer) }
    def end_offset; end

    sig { returns(Integer) }
    def start_line; end

    sig { returns(Integer) }
    def end_line; end

    sig { returns(Integer) }
    def start_column; end

    sig { returns(Integer) }
    def end_column; end

    sig { returns(String) }
    def slice; end
  end

  class ClassNode
    sig { returns(ConstantPathNode) }
    def constant_path; end
  end

  class ModuleNode
    sig { returns(ConstantPathNode) }
    def constant_path; end
  end
<<<<<<< HEAD
||||||| parent of 9e19894 (Migrate inlay hint)

  class DefNode
    sig { returns(String) }
    def name; end

    sig { returns(T.nilable(YARP::Node)) }
    def receiver; end

    sig { returns(Location) }
    def name_loc; end
  end

  class CallNode
    sig { returns(String) }
    def name; end

    sig { returns(T.nilable(ArgumentsNode)) }
    def arguments; end

    sig { returns(T.nilable(YARP::Node)) }
    def receiver; end
  end

  class ArgumentsNode
    sig { returns(T::Array[YARP::Node]) }
    def arguments; end
  end

  class StringNode
    sig { returns(String) }
    def content; end
  end

  class ConstantPathWriteNode
    sig { returns(YARP::Node) }
    def target; end
  end

  class SymbolNode
    sig { returns(String) }
    def value; end
  end

  class InstanceVariableWriteNode
    sig { returns(String) }
    def name; end

    sig { returns(Location) }
    def name_loc; end
  end

  class ClassVariableWriteNode
    sig { returns(String) }
    def name; end

    sig { returns(Location) }
    def name_loc; end
  end
=======

  class DefNode
    sig { returns(String) }
    def name; end

    sig { returns(T.nilable(YARP::Node)) }
    def receiver; end

    sig { returns(Location) }
    def name_loc; end
  end

  class CallNode
    sig { returns(String) }
    def name; end

    sig { returns(T.nilable(ArgumentsNode)) }
    def arguments; end

    sig { returns(T.nilable(YARP::Node)) }
    def receiver; end
  end

  class ArgumentsNode
    sig { returns(T::Array[YARP::Node]) }
    def arguments; end
  end

  class StringNode
    sig { returns(String) }
    def content; end
  end

  class ConstantPathWriteNode
    sig { returns(YARP::Node) }
    def target; end
  end

  class SymbolNode
    sig { returns(String) }
    def value; end
  end

  class InstanceVariableWriteNode
    sig { returns(String) }
    def name; end

    sig { returns(Location) }
    def name_loc; end
  end

  class ClassVariableWriteNode
    sig { returns(String) }
    def name; end

    sig { returns(Location) }
    def name_loc; end
  end

  class RescueNode
    sig { returns(T::Array[YARP::Node]) }
    def exceptions; end
  end
>>>>>>> 9e19894 (Migrate inlay hint)
end
