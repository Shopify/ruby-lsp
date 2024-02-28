import * as assert from "assert";

import * as vscode from "vscode";

import {
  Telemetry,
  TelemetryApi,
  TelemetryEvent,
  ConfigurationEvent,
  CodeLensEvent,
} from "../../telemetry";

class FakeApi implements TelemetryApi {
  public sentEvents: TelemetryEvent[];

  constructor() {
    this.sentEvents = [];
  }

  // eslint-disable-next-line @typescript-eslint/require-await
  async sendEvent(event: TelemetryEvent): Promise<void> {
    this.sentEvents.push(event);
  }
}

suite("Telemetry", () => {
  test("Events are sent via the defined API", async () => {
    const api = new FakeApi();
    const telemetry = new Telemetry(
      {
        extensionMode: vscode.ExtensionMode.Production,
      } as vscode.ExtensionContext,
      api,
    );
    const event: TelemetryEvent = {
      request: "textDocument/foldingRanges",
      requestTime: 0.005,
      lspVersion: "1.0.0",
      uri: "file:///test.rb",
      errorClass: "NoMethodError",
      errorMessage: "undefined method `visit` for nil:NilClass",
      params: '{"position": {"line": 0, "character": 0}}',
      backtrace: "test.rb:1:in `visit'\ntest.rb:5:in `block in <main>'",
      rubyVersion: "3.2.0",
      yjitEnabled: true,
    };

    await telemetry.sendEvent(event);
    assert.strictEqual(api.sentEvents[0], event);
  });

  test("The API object is acquired via command", async () => {
    // eslint-disable-next-line no-process-env
    if (!process.env.CI) {
      // This test can't pass locally because the private telemetry command is already registered. Trying to register it
      // again always throws errors
      return;
    }

    const api = new FakeApi();
    vscode.commands.registerCommand(
      "ruby-lsp.getPrivateTelemetryApi",
      () => api,
    );
    const telemetry = new Telemetry({
      extensionMode: vscode.ExtensionMode.Production,
    } as vscode.ExtensionContext);
    const event: TelemetryEvent = {
      request: "textDocument/foldingRanges",
      requestTime: 0.005,
      lspVersion: "1.0.0",
      uri: "file:///test.rb",
      errorClass: "NoMethodError",
      errorMessage: "undefined method `visit` for nil:NilClass",
      rubyVersion: "3.2.0",
      yjitEnabled: true,
    };

    await telemetry.sendEvent(event);
    assert.strictEqual(api.sentEvents[0], event);
  });

  test("Send configuration events emits telemetry for relevant configurations", async () => {
    const api = new FakeApi();
    const telemetry = new Telemetry(
      {
        extensionMode: vscode.ExtensionMode.Production,
        globalState: {
          get: () => undefined,
          update: () => Promise.resolve(),
        } as unknown,
      } as vscode.ExtensionContext,
      api,
    );

    await telemetry.sendConfigurationEvents();
    const featureConfigurations = vscode.workspace
      .getConfiguration("rubyLsp")
      .get("enabledFeatures")!;

    const expectedNumberOfEvents =
      4 + Object.keys(featureConfigurations).length;

    assert.strictEqual(api.sentEvents.length, expectedNumberOfEvents);

    api.sentEvents.forEach((event) => {
      assert.strictEqual(typeof (event as ConfigurationEvent).value, "string");
    });
  });

  test("Send code lens event includes configured server version", async () => {
    const api = new FakeApi();
    const telemetry = new Telemetry(
      {
        extensionMode: vscode.ExtensionMode.Production,
        globalState: {
          get: () => undefined,
          update: () => Promise.resolve(),
        } as unknown,
      } as vscode.ExtensionContext,
      api,
    );

    await telemetry.sendCodeLensEvent("test", "1.0.0");

    const codeLensEvent = api.sentEvents[0] as CodeLensEvent;
    assert.strictEqual(codeLensEvent.type, "test");
    assert.strictEqual(codeLensEvent.lspVersion, "1.0.0");
  });
});
