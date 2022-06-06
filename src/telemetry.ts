import * as vscode from "vscode";

export interface TelemetryEvent {
  request: string;
  requestTime: number;
  lspVersion: string;
  uri?: string;
  errorClass?: string;
  errorMessage?: string;
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

  async sendEvent(event: TelemetryEvent) {
    if (await this.initialize()) {
      return this.api!.sendEvent(event);
    }
  }

  private async initialize(): Promise<boolean> {
    try {
      if (!this.api) {
        this.api = await vscode.commands.executeCommand(
          "ruby-lsp.getPrivateTelemetryApi"
        );
      }

      return Boolean(this.api);
    } catch (_error) {
      // Do nothing if no telemetry api is available
      return false;
    }
  }
}
