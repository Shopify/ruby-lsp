# source://syntax_tree/SYNTAX_TREE_VERSION/lib/syntax_tree.rb#39
def foo
end

# source://mutex_m//mutex_m.rb#1
def bar
end

# source://syntax_tree//lib/syntax_tree.rb#39
def baz
end

# source://syntax_tree//lib/syntax_tree.rb#1
class Foo
end

# source://syntax_tree//lib/syntax_tree.rb#2
class Foo::Bar
end

# source://syntax_tree//lib/syntax_tree.rb#3
module Foo
end

# source://syntax_tree//lib/syntax_tree.rb#4
FOO = 1

# source://syntax_tree//lib/syntax_tree.rb#5
FOO::BAR = 1

# source://deleted//lib/foo.rb.rb#1
def baz
end
