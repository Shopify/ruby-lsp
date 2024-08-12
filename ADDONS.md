# Ruby LSP addons

> [!WARNING]
> The Ruby LSP addon system is currently experimental and subject to changes in the API

Need help writing addons? Consider joining the #ruby-lsp-addons channel in the [Ruby DX Slack
workspace](https://join.slack.com/t/ruby-dx/shared_invite/zt-2c8zjlir6-uUDJl8oIwcen_FS_aA~b6Q).

## Motivation and goals

Editor features that are specific to certain tools or frameworks can be incredibly powerful. Typically, language servers
are aimed at providing features for a particular programming language (like Ruby!) and not specific tools. This is
reasonable since not every programmer uses the same combination of tools.

Including tool specific functionality in the Ruby LSP would not scale well given the large number of tools in the
ecosystem. It would also create a bottleneck for authors to push new features. Building separate tooling, on the other
hand, increases fragmentation which tends to increase the effort required by users to configure their development
environments.

For these reasons, the Ruby LSP ships with an addon system that authors can use to enhance the behavior of the base LSP
with tool specific functionality, aimed at

- Allowing gem authors to export Ruby LSP addons from their own gems
- Allowing LSP features to be enhanced by addons present in the application the developer is currently working on
- Not requiring extra configuration from the user
- Seamlessly integrating with the base features of the Ruby LSP

## Guidelines

When building a Ruby LSP addon, refer to these guidelines to ensure a good developer experience.

- Performance over features. A single slow request may result in lack of responsiveness in the editor
- There are two types of LSP requests: automatic (e.g.: semantic highlighting) and user initiated (go to definition).
The performance of automatic requests is critical for responsiveness as they are executed every time the user types
- Avoid duplicate work where possible. If something can be computed once and memoized, like configurations, do it
- Do not mutate LSP state directly. Addons sometimes have access to important state such as document objects, which
should never be mutated directly, but instead through the mechanisms provided by the LSP specification - like text edits
- Do not overnotify users. It's generally annoying and diverts attention from the current task

## Building a Ruby LSP addon

**Note**: the Ruby LSP uses [Sorbet](https://sorbet.org/). We recommend using Sorbet in addons as well, which allows
authors to benefit from types declared by the Ruby LSP.

As an example, check out [Ruby LSP Rails](https://github.com/Shopify/ruby-lsp-rails), which is a Ruby LSP addon to
provide Rails related features.

### Activating the addon

The Ruby LSP discovers addons based on the existence of an `addon.rb` file placed inside a `ruby_lsp` folder.  For
example, `my_gem/lib/ruby_lsp/my_gem/addon.rb`. This file must declare the addon class, which can be used to perform any
necessary activation when the server starts.


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

      # Returns the name of the addon
      def name
        "Ruby LSP My Gem"
      end
    end
  end
end
```

### Listeners

An essential component to addons are listeners. All Ruby LSP requests are listeners that handle specific node types.

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
    puts "Hello, #{node.constant_path.slice}!"
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

This approach enables all addon responses to be captured in a single round of AST visits, greatly improving performance.


### Enhancing features

To enhance a request, the addon must create a listener that will collect extra results that will be automatically appended to the
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

      def create_hover_listener(response_builder, node_context, index, dispatcher)
        # Use the listener factory methods to instantiate listeners with parameters sent by the LSP combined with any
        # pre-computed information in the addon. These factory methods are invoked on every request
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

### Registering formatters

Gems may also provide a formatter to be used by the Ruby LSP. To do that, the addon must create a formatter runner and
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
  # If using Sorbet to develop the addon, then include this interface to make sure the class is properly implemented
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

Sometimes, addons may need to send asynchronous information to the client. For example, a slow request might want to
indicate progress or diagnostics may be computed in the background without blocking the language server.

For this purpose, all addons receive the message queue when activated, which is a thread queue that can receive
notifications for the client. The addon should keep a reference to this message queue and pass it to listeners that are
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
code is modified. If your addon uses a tool that is configured through a file (like RuboCop and its `.rubocop.yml`)
you can register for changes to these files and react when the configuration changes.

**Note**: you will receive events from `ruby-lsp` and other addons as well, in addition to your own registered ones.


```ruby
module RubyLsp
  module MyGem
    class Addon < ::RubyLsp::Addon
      def activate(global_state, message_queue)
        register_additional_file_watchers(global_state, message_queue)
      end

      def deactivate; end

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

### Ensuring consistent documentation

The Ruby LSP exports a Rake task to help authors make sure all of their listeners are documented and include demos and
examples of the feature in action. Configure the Rake task and run `bundle exec rake ruby_lsp:check_docs` on CI to
ensure documentation is always up to date and consistent.

```ruby
require "ruby_lsp/check_docs"

# The first argument is the file list including all of the listeners declared by the addon
# The second argument is the file list of GIF files with the demos of all listeners
RubyLsp::CheckDocs.new(
  FileList["#{__dir__}/lib/ruby_lsp/ruby_lsp_rails/**/*.rb"],
  FileList.new("#{__dir__}/misc/**/*.gif"),
)
```

### Dependency constraints

While we figure out a good design for the addons API, breaking changes are bound to happen. To avoid having your addon
accidentally break editor functionality, always restrict the dependency on the `ruby-lsp` gem based on minor versions
(breaking changes may land on minor versions until we reach v1.0.0).

```ruby
spec.add_dependency("ruby-lsp", "~> 0.6.0")
```

### Testing addons

When writing unit tests for addons, it's essential to keep in mind that code is rarely in its final state while the
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
