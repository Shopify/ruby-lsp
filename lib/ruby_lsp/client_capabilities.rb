# typed: strict
# frozen_string_literal: true

module RubyLsp
  # This class stores all client capabilities that the Ruby LSP and its add-ons depend on to ensure that we're
  # not enabling functionality unsupported by the editor connecting to the server
  class ClientCapabilities
    #: bool
    attr_reader :supports_watching_files,
      :supports_request_delegation,
      :window_show_message_supports_extra_properties,
      :supports_progress,
      :supports_diagnostic_refresh,
      :supports_code_lens_refresh

    #: -> void
    def initialize
      # The editor supports watching files. This requires two capabilities: dynamic registration and relative pattern
      # support
      @supports_watching_files = false #: bool

      # The editor supports request delegation. This is an experimental capability since request delegation has not been
      # standardized into the LSP spec yet
      @supports_request_delegation = false #: bool

      # The editor supports extra arbitrary properties for `window/showMessageRequest`. Necessary for add-ons to show
      # dialogs with user interactions
      @window_show_message_supports_extra_properties = false #: bool

      # Which resource operations the editor supports, like renaming files
      @supported_resource_operations = [] #: Array[String]

      # The editor supports displaying progress requests
      @supports_progress = false #: bool

      # The editor supports server initiated refresh for diagnostics
      @supports_diagnostic_refresh = false #: bool

      # The editor supports server initiated refresh for code lenses
      @supports_code_lens_refresh = false #: bool
    end

    #: (Hash[Symbol, untyped] capabilities) -> void
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
      @supports_code_lens_refresh = workspace_capabilities.dig(:codeLens, :refreshSupport) || false
    end

    #: -> bool
    def supports_rename?
      @supported_resource_operations.include?("rename")
    end
  end
end
