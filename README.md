![Build Status](https://github.com/Shopify/vscode-ruby-lsp/workflows/CI/badge.svg)

# vscode-ruby-lsp

VS Code extension for the [Ruby LSP gem](https://github.com/Shopify/ruby-lsp).

## Usage

Search for `vscode-ruby-lsp` in the extensions tab and click install.

### Telemetry

On its own, the Ruby LSP does not collect any telemetry by default, but it does support hooking up to a private metrics
service if desired.

In order to receive metrics requests, a private plugin must export the `ruby-lsp.getPrivateTelemetryApi` command, which should
return an object that implements the `TelemetryApi` interface defined [here](https://github.com/Shopify/vscode-ruby-lsp/blob/main/src/telemetry.ts).

Fields included by default are defined in `TelemetryEvent` [here](https://github.com/Shopify/vscode-ruby-lsp/blob/main/src/telemetry.ts).
The exported API object can add any other data of interest and publish it to a private service.

For example,

```typescript
// Create the API class in a private plugin
class MyApi implements TemeletryApi {
  sendEvent(event: TelemetryEvent): Promise<void> {
    // Add timestamp to collected metrics
    const payload = {
      timestamp: Date.now(),
      ...event,
    };

    // Send metrics to a private service
    myFavouriteHttpClient.post("private-metrics-url", payload);
  }
}

// Register the command to return an object of the API
vscode.commands.registerCommand(
  "ruby-lsp.getPrivateTelemetryApi",
  () => new MyApi()
);
```

### Debugging

Interactive debugging works for both running the extension or tests. In the debug panel, select whether to run the extension in development mode or run tests, set up some breakpoints and start with F5.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Shopify/vscode-ruby-lsp.
This project is intended to be a safe, welcoming space for collaboration, and contributors
are expected to adhere to the
[Contributor Covenant](https://github.com/Shopify/vscode-ruby-lsp/blob/main/CODE_OF_CONDUCT.md)
code of conduct.

## License

This extension is available as open source under the terms of the
[MIT License](https://github.com/Shopify/vscode-ruby-lsp/blob/main/LICENSE.txt).
