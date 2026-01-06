# source://syntax_tree/SYNTAX_TREE_VERSION/lib/syntax_tree.rb#39
def foo
end

# source://open3//open3.rb#1
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

# Various URIs crafted to attempt to make `URI::Source#host` nil.
# All of these will be filtered out, and not appear in the expectation file.

# source:+1-800-555-5555
def attempt_to_make_empty_host_1; end

# source:
def attempt_to_make_empty_host_2; end

# source:/
def attempt_to_make_empty_host_3; end

# source://
def attempt_to_make_empty_host_4; end

# source:///
def attempt_to_make_empty_host_5; end

# source:#123
def attempt_to_make_empty_host_6; end

# source:/#123
def attempt_to_make_empty_host_7; end

# source://#123
def attempt_to_make_empty_host_8; end

# source:///#123
def attempt_to_make_empty_host_9; end
