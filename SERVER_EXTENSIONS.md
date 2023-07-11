# Server extensions

> **WARNING**
> The Ruby LSP server extensions system is currently experimental and subject to changes in the API

Need help writing extensions? Consider joining the #ruby-lsp-extensions channel in the [Ruby DX Slack
workspace](https://join.slack.com/t/ruby-dx/shared_invite/zt-1s6f4y15t-v9jedZ9YUPQLM91TEJ4Gew).

## Motivation and goals

Editor features that are specific to certain tools or frameworks can be incredibly powerful. Typically, language servers
are aimed at providing features for a particular programming language (like Ruby!) and not specific tools. This is
reasonable since not every programmer uses the same combination of tools.

Including tool specific functionality in the Ruby LSP would not scale well given the large number of tools in the
ecosystem. It would also create a bottleneck for authors to push new features. Building separate tooling, on the other
hand, increases fragmentation which tends to increase the effort required by users to configure their development
environments.

For these reasons, the Ruby LSP ships with a server extension system that authors can use to enhance the behavior of the
base LSP with tool specific functionality, aimed at

- Allowing gem authors to export Ruby LSP extensions from their own gems
- Allowing LSP features to be enhanced by extensions present in the application the developer is currently working on
- Not requiring extra configuration from the user
- Seamlessly integrating with the base features of the Ruby LSP

## Guidelines

When building a Ruby LSP extension, refer to these guidelines to ensure a good developer experience.

- Performance over features. A single slow request may result in lack of responsiveness in the editor
- There are two types of LSP requests: automatic (e.g.: semantic highlighting) and user initiated (go to definition).
The performance of automatic requests is critical for responsiveness as they are executed every time the user types
- Avoid duplicate work where possible. If something can be computed once and memoized, like configurations, do it
- Do not mutate LSP state directly. Extensions sometimes have access to important state such as document objects, which
should never be mutated directly, but instead through the mechanisms provided by the LSP specification - like text edits
- Do not overnotify users. It's generally annoying and diverts attention from the current task

## Building a Ruby LSP extension

**Note**: the Ruby LSP uses [Sorbet](https://sorbet.org/). We recommend using Sorbet in extensions as well, which allows
authors to benefit from types declared by the Ruby LSP.

As an example, check out [Ruby LSP Rails](https://github.com/Shopify/ruby-lsp-rails), which is a Ruby LSP extension to
provide Rails related features.

### Activating the extension

The Ruby LSP discovers extensions based on the existence of an `extension.rb` file placed inside a `ruby_lsp` folder.
For example, `my_gem/lib/ruby_lsp/my_gem/extension.rb`. This file must declare the extension class, which can be used to
perform any necessary activation when the server starts.


```ruby
# frozen_string_literal: true

require "ruby_lsp/extension"

module RubyLsp
  module MyGem
    class Extension < ::RubyLsp::Extension
      extend T::Sig

      # Performs any activation that needs to happen once when the language server is booted in addition to registering
      # listeners and request enhancements
      sig { override.void }
      def activate
        # Register the MyGem::Hover listener to enhance hover functionality
        # IMPORTANT: listener and request enhancement registration must be done inside `activate`
        ::RubyLsp::Requests::Hover.add_listener(MyGem::Hover)
      end

      # Returns the name of the extension
      sig { override.returns(String) }
      def name
        "Ruby LSP My Gem"
      end
    end
  end
end
```

### Enhancing features

All Ruby LSP requests are listeners that handle specific node types. To enhance a request, the extension must create and
register a listener that will collect extra results that will be automatically appended to the base language server
response.

For example: to add a message on hover saying "Hello!" on top of the base hover behavior of the Ruby LSP, we can use the
following listener implementation.

```ruby
# frozen_string_literal: true

module RubyLsp
  module MyGem
    # All listeners have to inherit from ::RubyLsp::Listener
    class Hover < ::RubyLsp::Listener
      extend T::Sig
      extend T::Generic

      ResponseType = type_member { { fixed: T.nilable(::RubyLsp::Interface::Hover) } }

      sig { override.returns(ResponseType) }
      attr_reader :response

      # Listeners are initialized with the EventEmitter. This object is used by the Ruby LSP to emit the events when it
      # finds nodes during AST analysis. Listeners must register which nodes they want to handle with the emitter (see
      # below).
      # Additionally, listeners are instantiated with a message_queue to push notifications (not used in this example).
      # See "Sending notifications to the client" for more information.
      sig { params(emitter: RubyLsp::EventEmitter, message_queue: Thread::Queue).void }
      def initialize(emitter, message_queue)
        super

        @response = T.let(nil, ResponseType)

        # Register that this listener will handle `on_const` events (i.e.: whenever a constant is found in the code)
        emitter.register(self, :on_const)
      end

      # Listeners must define methods for each event they registered with the emitter. In this case, we have to define
      # `on_const` to specify what this listener should do every time we find a constant
      sig { params(node: SyntaxTree::Const).void }
      def on_const(node)
        # Certain helpers are made available to listeners to build LSP responses. The classes under `RubyLsp::Interface`
        # are generally used to build responses and they match exactly what the specification requests.
        contents = RubyLsp::Interface::MarkupContent.new(kind: "markdown", value: "Hello!")
        @response = RubyLsp::Interface::Hover.new(range: range_from_syntax_tree_node(node), contents: contents)
      end
    end
  end
end
```

### Registering formatters

Gems may also provide a formatter to be used by the Ruby LSP. To do that, the extension must create a formatter runner
and register it. The formatter is used if the `rubyLsp.formatter` option configured by the user matches the identifier
registered.

```ruby
class MyFormatterRubyLspExtension < RubyLsp::Extension
  def name
    "My Formatter"
  end

  def activate
    # The first argument is an identifier users can pick to select this formatter. To use this formatter, users must
    # have rubyLsp.formatter configured to "my_formatter"
    # The second argument is a singleton instance that implements the `FormatterRunner` interface (see below)
    RubyLsp::Requests::Formatting.register_formatter("my_formatter", MyFormatterRunner.instance)
  end
end

# Custom formatting runner
class MyFormatterRunner
  # Make it a singleton class
  include Singleton
  # If using Sorbet to develop the extension, then include this interface to make sure the class is properly implemented
  include RubyLsp::Requests::Support::FormatterRunner

  # Use the initialize method to perform any sort of ahead of time work. For example, reading configurations for your
  # formatter since they are unlikely to change between requests
  def initialize
  end

  # The main part of the interface is implementing the run method. It receives the URI and the document being formatted.
  # IMPORTANT: This method must return the formatted document source without mutating the original one in document
  def run(uri, document)
    source = document.source
    formatted_source = format_the_source_using_my_formatter(source)
    formatted_source
  end
end
```

### Sending notifications to the client

Sometimes, requests may want to send asynchronous information to the client. For example, a slow request may want to
indicate progress. To send notifications, all listeners have access to the message queue, where they can push
notifications to the client.

```ruby
class MyListener < ::RubyLsp::Listener
  def initialize(emitter, message_queue)
    super

    @message_queue << Notification.new(
      message: "$/progress",
      params: Interface::ProgressParams.new(
        token: "progress-token-id",
        value: Interface::WorkDoneProgressBegin.new(kind: "begin", title: "Starting slow work!"),
      )
    )
  end
end
```

### Ensuring consistent documentation

The Ruby LSP exports a Rake task to help authors make sure all of their listeners are documented and include demos and
examples of the feature in action. Configure the Rake task and run `bundle exec rake ruby_lsp:check_docs` on CI to
ensure documentation is always up to date and consistent.

```ruby
require "ruby_lsp/check_docs"

# The first argument is the file list including all of the listeners declared by the extension
# The second argument is the file list of GIF files with the demos of all listeners
RubyLsp::CheckDocs.new(
  FileList["#{__dir__}/lib/ruby_lsp/ruby_lsp_rails/**/*.rb"],
  FileList.new("#{__dir__}/misc/**/*.gif")
)
```

### Dependency constraints

While we figure out a good design for the extensions API, breaking changes are bound to happen. To avoid having your
extension accidentally break editor functionality, always restrict the dependency on the `ruby-lsp` gem based on minor
versions (breaking changes may land on minor versions until we reach v1.0.0).

```ruby
spec.add_dependency("ruby-lsp", "~> 0.6.0")
```

### Testing extensions

When writing unit tests for extensions, it's essential to keep in mind that code is rarely in its final state while the
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
