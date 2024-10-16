---
layout: default
title: Add-ons
nav_order: 10
parent: Ruby LSP
---

# Add-ons

{: .warning }
> The Ruby LSP add-on system is currently experimental and subject to changes in the API

Need help writing add-ons? Consider joining the `#ruby-lsp-addons` channel in the [Ruby DX Slack
workspace](https://join.slack.com/t/ruby-dx/shared_invite/zt-2c8zjlir6-uUDJl8oIwcen_FS_aA~b6Q).

## Motivation and goals

Editor features that are specific to certain tools or frameworks can be incredibly powerful. Typically, language servers
are aimed at providing features for a particular programming language (like Ruby!) and not specific tools. This is
reasonable since not every programmer uses the same combination of tools.

Including tool specific functionality in the Ruby LSP would not scale well given the large number of tools in the
ecosystem. It would also create a bottleneck for authors to push new features. Building separate tooling, on the other
hand, increases fragmentation which tends to increase the effort required by users to configure their development
environments.

For these reasons, the Ruby LSP ships with an add-on system that authors can use to enhance the behavior of the base LSP
with tool specific functionality, aimed at

- Allowing gem authors to export Ruby LSP add-ons from their own gems
- Allowing LSP features to be enhanced by add-ons present in the application the developer is currently working on
- Not requiring extra configuration from the user
- Seamlessly integrating with the base features of the Ruby LSP
- Providing add-on authors with the entire static analysis toolkit that the Ruby LSP uses

## Guidelines

When building a Ruby LSP add-on, refer to these guidelines to ensure a good developer experience.

- Performance over features. A single slow request may result in lack of responsiveness in the editor
- There are two types of LSP requests: automatic (e.g.: semantic highlighting) and user initiated (go to definition).
The performance of automatic requests is critical for responsiveness as they are executed every time the user types
- Avoid duplicate work where possible. If something can be computed once and memoized, like configurations, do it
- Do not mutate LSP state directly. Add-ons sometimes have access to important state such as document objects, which
should never be mutated directly, but instead through the mechanisms provided by the LSP specification - like text edits
- Do not over-notify users. It's generally annoying and diverts attention from the current task
- Show the right context at the right time. When adding visual features, think about **when** the information is
relevant for users to avoid polluting the editor

## Building a Ruby LSP add-on

**Note**: the Ruby LSP uses [Sorbet](https://sorbet.org/). We recommend using Sorbet in add-ons as well, which allows
authors to benefit from types declared by the Ruby LSP.

As an example, check out [Ruby LSP Rails](https://github.com/Shopify/ruby-lsp-rails), which is a Ruby LSP add-on to
provide Rails related features.

### Activating the add-on

The Ruby LSP discovers add-ons based on the existence of an `addon.rb` file placed inside a `ruby_lsp` folder.  For
example, `my_gem/lib/ruby_lsp/my_gem/addon.rb`. This file must declare the add-on class, which can be used to perform any
necessary activation when the server starts.

{: .note }
Projects can also define their own private add-ons for functionality that only applies to a particular application. As
long as a file matching `ruby_lsp/**/addon.rb` exists inside of the workspace (not necessarily at the root), it will be
loaded by the Ruby LSP.

```ruby
# frozen_string_literal: true

require "ruby_lsp/addon"

module RubyLsp
  module MyGem
    class Addon < ::RubyLsp::Addon
      # Performs any activation that needs to happen once when the language server is booted
      def activate(global_state, message_queue)
      end

      # Performs any cleanup when shutting down the server, like terminating a subprocess
      def deactivate
      end

      # Returns the name of the add-on
      def name
        "Ruby LSP My Gem"
      end

      # Defining a version for the add-on is mandatory. This version doesn't necessarily need to match the version of
      # the gem it belongs to
      def version
        "0.1.0"
      end
    end
  end
end
```

### Listeners

An essential component to add-ons are listeners. All Ruby LSP requests are listeners that handle specific node types.

Listeners work in conjunction with a `Prism::Dispatcher`, which is responsible for dispatching events during the parsing of Ruby code. Each event corresponds to a specific node in the Abstract Syntax Tree (AST) of the code being parsed.

Here's a simple example of a listener:

```ruby
# frozen_string_literal: true

class MyListener
  def initialize(dispatcher)
    # Register to listen to `on_class_node_enter` events
    dispatcher.register(self, :on_class_node_enter)
  end

  # Define the handler method for the `on_class_node_enter` event
  def on_class_node_enter(node)
    $stderr.puts "Hello, #{node.constant_path.slice}!"
  end
end

dispatcher = Prism::Dispatcher.new
MyListener.new(dispatcher)

parse_result = Prism.parse("class Foo; end")
dispatcher.dispatch(parse_result.value)

# Prints
# => Hello, Foo!
```

In this example, the listener is registered to the dispatcher to listen for the `:on_class_node_enter` event. When a class node is encountered during the parsing of the code, a greeting message is outputted with the class name.

This approach enables all add-on responses to be captured in a single round of AST visits, greatly improving performance.

### Enhancing features

There are two ways to enhance Ruby LSP features. One is handling DSLs that occur at a call site and that do not change
which declarations exist in the project. A great example of this is the Rails `validate` method, which accepts a symbol
that represents a method that gets dynamically invoked. That style of DSL is what we refer to as a [call site
DSL](#dealing-with-call-site-dsls).

```ruby
class User < ApplicationRecord
  # From Ruby's perspective, `:something` is just a regular symbol. It's Rails that defines this as a DSL and specifies
  # that the argument represents a method name.
  #
  # If an add-on wanted to handle go to definition or completion for these symbols, then it would need to enhance the
  # handling for call site DSLs
  validate :something

  private

  def something
  end
end
```

The second way to augment the Ruby LSP is to handle declaration DSLs. These are DSLs that create declarations via
meta-programming. To use another Rails example, `belongs_to` is a DSL that mutates the current class and adds extra
methods based on the arguments passed to it.

DSLs that add extra declarations should be handled through an [indexing enhancement](#dealing-with-declaration-dsls).

```ruby
class User < ApplicationRecord
  # When this method is invoked, a bunch of new methods will be defined in the `User` class, such as `company` and
  # `company=`. By informing the Ruby LSP about the new methods through an indexing enhancement, features such as
  # go to definition, completion, hover, signature help and workspace symbol will automatically pick up the new
  # declaration
  belongs_to :company
end
```

#### Dealing with call site DSLs

To enhance a request, the add-on must create a listener that will collect extra results that will be automatically appended to the
base language server response. Additionally, `Addon` has to implement a factory method that instantiates the listener. When instantiating the
listener, also note that a `ResponseBuilders` object is passed in. This object should be used to return responses back to the Ruby LSP.

For example: to add a message on hover saying "Hello!" on top of the base hover behavior of the Ruby LSP, we can use the
following listener implementation.

```ruby
# frozen_string_literal: true

module RubyLsp
  module MyGem
    class Addon < ::RubyLsp::Addon
      def activate(global_state, message_queue)
        @message_queue = message_queue
        @config = SomeConfiguration.new
      end

      def deactivate
      end

      def name
        "Ruby LSP My Gem"
      end

      def version
        "0.1.0"
      end

      def create_hover_listener(response_builder, node_context, index, dispatcher)
        # Use the listener factory methods to instantiate listeners with parameters sent by the LSP combined with any
        # pre-computed information in the add-on. These factory methods are invoked on every request
        Hover.new(client, response_builder, @config, dispatcher)
      end
    end

    class Hover
      # The Requests::Support::Common module provides some helper methods you may find helpful.
      include Requests::Support::Common

      # Listeners are initialized with the Prism::Dispatcher. This object is used by the Ruby LSP to emit the events
      # when it finds nodes during AST analysis. Listeners must register which nodes they want to handle with the
      # dispatcher (see below).
      # Listeners are initialized with a `ResponseBuilders` object. The listener will push the associated content
      # to this object, which will then build the Ruby LSP's response.
      # Additionally, listeners are instantiated with a message_queue to push notifications (not used in this example).
      # See "Sending notifications to the client" for more information.
      def initialize(client, response_builder, config, dispatcher)
        super(dispatcher)

        @client = client
        @response_builder = response_builder
        @config = config

        # Register that this listener will handle `on_constant_read_node_enter` events (i.e.: whenever a constant read
        # is found in the code)
        dispatcher.register(self, :on_constant_read_node_enter)
      end

      # Listeners must define methods for each event they registered with the dispatcher. In this case, we have to
      # define `on_constant_read_node_enter` to specify what this listener should do every time we find a constant
      def on_constant_read_node_enter(node)
        # Certain builders are made available to listeners to build LSP responses. The classes under
        # `RubyLsp::ResponseBuilders` are used to build responses conforming to the LSP Specification.
        # ResponseBuilders::Hover itself also requires a content category to be specified (title, links,
        # or documentation).
        @response_builder.push("Hello!", category: :documentation)
      end
    end
  end
end
```

#### Dealing with declaration DSLs

Add-ons can inform the Ruby LSP about declarations that are made via meta-programming. By ensuring that the index is
populated with all declarations, features like go to definition, hover, completion, signature help and workspace symbol
will all automatically work.

To achieve this the add-on must create an indexing enhancement class and register it. Here's an example of how to do
it. Consider that a gem defines this DSL:

```ruby
class MyThing < MyLibrary::ParentClass
  # After invoking this method from the `MyLibrary::ParentClass`, a method called `new_method` will be created,
  # accepting a single required parameter named `a`
  my_dsl_that_creates_methods

  # Produces this with meta-programming
  # def my_method(a); end
end
```

This is how you could write an enhancement to teach the Ruby LSP to understand that DSL:

```ruby
class MyIndexingEnhancement
  include RubyLsp::Enhancement

  # This on call node handler is invoked any time during indexing when we find a method call. It can be used to insert
  # more entries into the index depending on the conditions
  def on_call_node(index, owner, node, file_path)
    return unless owner

    # Get the ancestors of the current class
    ancestors = index.linearized_ancestors_of(owner.name)

    # Return early unless the method call is the one we want to handle and the class invoking the DSL inherits from
    # our library's parent class
    return unless node.name == :my_dsl_that_creates_methods && ancestors.include?("MyLibrary::ParentClass")

    # Create a new entry to be inserted in the index. This entry will represent the declaration that is created via
    # meta-programming. All entries are defined in the `entry.rb` file.
    #
    # In this example, we will add a new method to the index
    location = node.location

    # Create the array of signatures that this method will accept. Every signatures is composed of a list of
    # parameters. The parameter classes represent each type of parameter
    signatures = [
      Entry::Signature.new([Entry::RequiredParameter.new(name: :a)])
    ]

    new_entry = Entry::Method.new(
      "new_method", # The name of the method that gets created via meta-programming
      file_path,    # The file_path where the DSL call was found. This should always just be the file_path received
      location,     # The Prism node location where the DSL call was found
      location,     # The Prism node location for the DSL name location. May or not be the same
      nil,          # The documentation for this DSL call. This should always be `nil` to ensure lazy fetching of docs
      index.configuration.encoding, # The negotiated encoding. This should always be `indexing.configuration.encoding`
      signatures,   # All signatures for this method (every way it can be invoked)
      Entry::Visibility::PUBLIC, # The method's visibility
      owner,        # The method's owner. This is almost always going to be the same owner received
    )

    # Push the new entry to the index
    index.add(new_entry)
  end
end
```

Finally, we need to register our enhancement in the index once during the add-on's activation.

```ruby
module RubyLsp
  module MyLibrary
    class Addon < ::RubyLsp::Addon
      def activate(global_state, message_queue)
        # Register the enhancement as part of the indexing process
        @index.register_enhancement(MyIndexingEnhancement.new)
      end

      def deactivate
      end

      def name
        "MyLibrary"
      end

      def version
        "0.1.0"
      end
    end
  end
end
```

Done! With this the Ruby LSP should automatically handle calls to `my_dsl_that_creates_methods` and create an accurate
representation of the declarations that will be available in the runtime.

### Registering formatters

Gems may also provide a formatter to be used by the Ruby LSP. To do that, the add-on must create a formatter runner and
register it. The formatter is used if the `rubyLsp.formatter` option configured by the user matches the identifier
registered.

```ruby
class MyFormatterRubyLspAddon < RubyLsp::Addon
  def name
    "My Formatter"
  end

  def activate(global_state, message_queue)
    # The first argument is an identifier users can pick to select this formatter. To use this formatter, users must
    # have rubyLsp.formatter configured to "my_formatter"
    # The second argument is a class instance that implements the `FormatterRunner` interface (see below)
    global_state.register_formatter("my_formatter", MyFormatterRunner.new)
  end
end

# Custom formatter
class MyFormatter
  # If using Sorbet to develop the add-on, then include this interface to make sure the class is properly implemented
  include RubyLsp::Requests::Support::Formatter

  # Use the initialize method to perform any sort of ahead of time work. For example, reading configurations for your
  # formatter since they are unlikely to change between requests
  def initialize
    @config = read_config_file!
  end

  # IMPORTANT: None of the following methods should mutate the document in any way or that will lead to a corrupt state!

  # Provide formatting for a given document. This method should return the formatted string for the entire document
  def run_formatting(uri, document)
    source = document.source
    formatted_source = format_the_source_using_my_formatter(source)
    formatted_source
  end

  # Provide diagnostics for the given document. This method must return an array of `RubyLsp::Interface::Diagnostic`
  # objects
  def run_diagnostic(uri, document)
  end
end
```

### Sending notifications to the client

Sometimes, add-ons may need to send asynchronous information to the client. For example, a slow request might want to
indicate progress or diagnostics may be computed in the background without blocking the language server.

For this purpose, all add-ons receive the message queue when activated, which is a thread queue that can receive
notifications for the client. The add-on should keep a reference to this message queue and pass it to listeners that are
interested in using it.

**Note**: do not close the message queue anywhere. The Ruby LSP will handle closing the message queue when appropriate.

```ruby
module RubyLsp
  module MyGem
    class Addon < ::RubyLsp::Addon
      def activate(global_state, message_queue)
        @message_queue = message_queue
      end

      def deactivate; end

      def name
        "Ruby LSP My Gem"
      end

      def version
        "0.1.0"
      end

      def create_hover_listener(response_builder, node_context, index, dispatcher)
        MyHoverListener.new(@message_queue, response_builder, node_context, index, dispatcher)
      end
    end

    class MyHoverListener
      def initialize(message_queue, response_builder, node_context, index, dispatcher)
        @message_queue = message_queue

        @message_queue << Notification.new(
          message: "$/progress",
          params: Interface::ProgressParams.new(
            token: "progress-token-id",
            value: Interface::WorkDoneProgressBegin.new(kind: "begin", title: "Starting slow work!"),
          ),
        )
      end
    end
  end
end
```

### Registering for file update events

By default, the Ruby LSP listens for changes to files ending in `.rb` to continuously update its index when Ruby source
code is modified. If your add-on uses a tool that is configured through a file (like RuboCop and its `.rubocop.yml`)
you can register for changes to these files and react when the configuration changes.

**Note**: you will receive events from `ruby-lsp` and other add-ons as well, in addition to your own registered ones.


```ruby
module RubyLsp
  module MyGem
    class Addon < ::RubyLsp::Addon
      def activate(global_state, message_queue)
        register_additional_file_watchers(global_state, message_queue)
      end

      def deactivate; end

      def version
        "0.1.0"
      end

      def name
        "My Addon"
      end

      def register_additional_file_watchers(global_state, message_queue)
        # Clients are not required to implement this capability
        return unless global_state.supports_watching_files

        message_queue << Request.new(
          id: "ruby-lsp-my-gem-file-watcher",
          method: "client/registerCapability",
          params: Interface::RegistrationParams.new(
            registrations: [
              Interface::Registration.new(
                id: "workspace/didChangeWatchedFilesMyGem",
                method: "workspace/didChangeWatchedFiles",
                register_options: Interface::DidChangeWatchedFilesRegistrationOptions.new(
                  watchers: [
                    Interface::FileSystemWatcher.new(
                      glob_pattern: "**/.my-config.yml",
                      kind: Constant::WatchKind::CREATE | Constant::WatchKind::CHANGE | Constant::WatchKind::DELETE,
                    ),
                  ],
                ),
              ),
            ],
          ),
        )
      end

      def workspace_did_change_watched_files(changes)
        if changes.any? { |change| change[:uri].end_with?(".my-config.yml") }
          # Do something to reload the config here
        end
      end
    end
  end
end
```

### Dependency constraints

While we figure out a good design for the add-ons API, breaking changes are bound to happen. To avoid having your
add-on accidentally break editor functionality, you should define the version that your add-on depends on. There are
two ways of achieving this.

#### Add-ons that have a runtime dependency on the ruby-lsp

For add-ons that have a runtime dependency on the `ruby-lsp` gem, you can simply use regular gemspec constraints to
define which version is supported.

```ruby
spec.add_dependency("ruby-lsp", "~> 0.6.0")
```

#### Add-ons that do not have a runtime dependency on the ruby-lsp

For add-ons that are defined inside other gems that do not wish to have a runtime dependency on `ruby-lsp`, please use
the following API to ensure compatibility.

{: .note }
If the Ruby LSP is automatically upgraded to a version not supported by an add-on using this approach, the add-on will
simply not be activated with a warning and the functionality will not be available. The author must update to ensure
compatibility with the current state of the API.

```ruby

# Declare that this add-on supports the base Ruby LSP version v0.18.0, but not v0.19 or above
#
# If the Ruby LSP is upgraded to v0.19.0, this add-on will fail gracefully to activate and a warning will be printed
RubyLsp::Addon.depend_on_ruby_lsp!("~> 0.18.0")

module RubyLsp
  module MyGem
    class Addon < ::RubyLsp::Addon
      def activate(global_state, message_queue)
      end

      def deactivate; end

      def version
        "0.1.0"
      end

      def name
        "My Addon"
      end
    end
  end
end
```

### Testing add-ons

When writing unit tests for add-ons, it's essential to keep in mind that code is rarely in its final state while the
developer is coding. Therefore, be sure to test valid scenarios where the code is still incomplete.

For example, if you are writing a feature related to `require`, do not test `require "library"` exclusively. Consider
intermediate states the user might end up while typing. Additionally, consider syntax that is uncommon, yet still valid
Ruby.

```ruby
# Still no argument
require

# With quotes autocompleted, but no content on the string
require ""

# Using uncommon, but valid syntax, such as invoking require directly on Kernel using parenthesis
Kernel.require("library")
```

The Ruby LSP exports a test helper which creates a server instance with a document already initialized with the desired
content. This is useful to test the integration of your add-on with the language server.

Add-ons are automatically loaded, so simply executing the desired language server request should already include your
add-on's contributions.

```ruby
require "test_helper"
require "ruby_lsp/test_helper"

class MyAddonTest < Minitest::Test
  def test_my_addon_works
    source =  <<~RUBY
      # Some test code that allows you to trigger your add-on's contribution
      class Foo
        def something
        end
      end
    RUBY

    with_server(source) do |server, uri|
      # Tell the server to execute the definition request
      server.process_message(
        id: 1,
        method: "textDocument/definition",
        params: {
          textDocument: {
            uri: uri.to_s,
          },
          position: {
            line: 3,
            character: 5
          }
        }
      )

      # Pop the server's response to the definition request
      result = server.pop_response.response
      # Assert that the response includes your add-on's contribution
      assert_equal(123, result.response.location)
    end
  end
end
```
