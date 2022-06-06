import * as assert from "assert";

import * as vscode from "vscode";

import { Telemetry, TelemetryApi, TelemetryEvent } from "../../telemetry";

class FakeApi implements TelemetryApi {
  public sentEvents: TelemetryEvent[];

  constructor() {
    this.sentEvents = [];
  }

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
      api
    );
    const event: TelemetryEvent = {
      request: "textDocument/foldingRanges",
      requestTime: 0.005,
      lspVersion: "1.0.0",
      uri: "file:///test.rb",
      errorClass: "NoMethodError",
      errorMessage: "undefined method `visit` for nil:NilClass",
    };

    await telemetry.sendEvent(event);
    assert.strictEqual(api.sentEvents[0], event);
  });

  test("The API object is acquired via command", async () => {
    const api = new FakeApi();
    vscode.commands.registerCommand(
      "ruby-lsp.getPrivateTelemetryApi",
      () => api
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
    };

    await telemetry.sendEvent(event);
    assert.strictEqual(api.sentEvents[0], event);
  });
});
