import * as vscode from "vscode";

export interface TelemetryEvent {
  request: string;
  requestTime: number;
  lspVersion: string;
  uri?: string;
}

export interface TelemetryApi {
  sendEvent(event: TelemetryEvent): Promise<void>;
}

class DevelopmentApi implements TelemetryApi {
  async sendEvent(event: TelemetryEvent): Promise<void> {
    // eslint-disable-next-line no-console
    console.log(event);
  }
}

export class Telemetry {
  private api?: TelemetryApi;

  constructor(context: vscode.ExtensionContext, api?: TelemetryApi) {
    if (context.extensionMode === vscode.ExtensionMode.Development && !api) {
      this.api = new DevelopmentApi();
    } else {
      this.api = api;
    }
  }

  async initialize() {
    try {
      this.api = await vscode.commands.executeCommand(
        "ruby-lsp.getPrivateTelemetryApi"
      );
    } catch (_error) {
      // Do nothing if no telemetry api is available
    }
  }

  async sendEvent(event: TelemetryEvent) {
    if (this.api) {
      return this.api.sendEvent(event);
    }
  }

  enabled(): boolean {
    return Boolean(this.api);
  }
}
