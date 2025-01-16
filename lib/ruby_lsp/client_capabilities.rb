# typed: strict
# frozen_string_literal: true

module RubyLsp
  # This class stores all client capabilities that the Ruby LSP and its add-ons depend on to ensure that we're
  # not enabling functionality unsupported by the editor connecting to the server
  class ClientCapabilities
    extend T::Sig

    sig { returns(T::Boolean) }
    attr_reader :supports_watching_files,
      :supports_request_delegation,
      :window_show_message_supports_extra_properties,
      :supports_progress,
      :supports_diagnostic_refresh

    sig { void }
    def initialize
      # The editor supports watching files. This requires two capabilities: dynamic registration and relative pattern
      # support
      @supports_watching_files = T.let(false, T::Boolean)

      # The editor supports request delegation. This is an experimental capability since request delegation has not been
      # standardized into the LSP spec yet
      @supports_request_delegation = T.let(false, T::Boolean)

      # The editor supports extra arbitrary properties for `window/showMessageRequest`. Necessary for add-ons to show
      # dialogs with user interactions
      @window_show_message_supports_extra_properties = T.let(false, T::Boolean)

      # Which resource operations the editor supports, like renaming files
      @supported_resource_operations = T.let([], T::Array[String])

      # The editor supports displaying progress requests
      @supports_progress = T.let(false, T::Boolean)

      # The editor supports server initiated refresh for diagnostics
      @supports_diagnostic_refresh = T.let(false, T::Boolean)
    end

    sig { params(capabilities: T::Hash[Symbol, T.untyped]).void }
    def apply_client_capabilities(capabilities)
      workspace_capabilities = capabilities[:workspace] || {}

      file_watching_caps = workspace_capabilities[:didChangeWatchedFiles]
      if file_watching_caps&.dig(:dynamicRegistration) && file_watching_caps&.dig(:relativePatternSupport)
        @supports_watching_files = true
      end

      @supports_request_delegation = capabilities.dig(:experimental, :requestDelegation) || false
      supported_resource_operations = workspace_capabilities.dig(:workspaceEdit, :resourceOperations)
      @supported_resource_operations = supported_resource_operations if supported_resource_operations

      supports_additional_properties = capabilities.dig(
        :window,
        :showMessage,
        :messageActionItem,
        :additionalPropertiesSupport,
      )
      @window_show_message_supports_extra_properties = supports_additional_properties || false

      progress = capabilities.dig(:window, :workDoneProgress)
      @supports_progress = progress if progress

      @supports_diagnostic_refresh = workspace_capabilities.dig(:diagnostics, :refreshSupport) || false
    end

    sig { returns(T::Boolean) }
    def supports_rename?
      @supported_resource_operations.include?("rename")
    end
  end
end
