import * as vscode from "vscode";

interface RequestEvent {
  request: string;
  requestTime: number;
  lspVersion: string;
  uri?: string;
  errorClass?: string;
  errorMessage?: string;
  backtrace?: string;
  params?: string;
  rubyVersion: string;
  yjitEnabled: boolean;
}

export interface ConfigurationEvent {
  namespace: string;
  field: string;
  value: string;
}

export interface CodeLensEvent {
  type: "test" | "debug" | "test_in_terminal" | "link";
  lspVersion: string;
}

export type TelemetryEvent = RequestEvent | ConfigurationEvent | CodeLensEvent;

const ONE_DAY_IN_MS = 24 * 60 * 60 * 1000;

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
  public serverVersion?: string;
  private api?: TelemetryApi;
  private context: vscode.ExtensionContext;

  constructor(context: vscode.ExtensionContext, api?: TelemetryApi) {
    this.context = context;

    if (context.extensionMode === vscode.ExtensionMode.Development && !api) {
      this.api = new DevelopmentApi();
    } else {
      this.api = api;
    }
  }

  async sendEvent(event: TelemetryEvent) {
    if (await this.initialize()) {
      this.api!.sendEvent(event);
    }
  }

  async sendConfigurationEvents() {
    const lastConfigurationTelemetry: number | undefined =
      this.context.globalState.get("rubyLsp.lastConfigurationTelemetry");

    if (
      lastConfigurationTelemetry &&
      Date.now() - lastConfigurationTelemetry <= ONE_DAY_IN_MS
    ) {
      return;
    }

    const promises: Promise<void>[] = [
      { namespace: "workbench", field: "colorTheme" },
      { namespace: "rubyLsp", field: "enableExperimentalFeatures" },
      { namespace: "rubyLsp", field: "yjit" },
      { namespace: "rubyLsp", field: "rubyVersionManager" },
      { namespace: "rubyLsp", field: "formatter" },
    ].map(({ namespace, field }) => {
      return this.sendEvent({
        namespace,
        field,
        value: (
          vscode.workspace.getConfiguration(namespace).get(field) ?? ""
        ).toString(),
      });
    });

    const enabledFeatures = vscode.workspace
      .getConfiguration("rubyLsp")
      .get("enabledFeatures")!;

    Object.entries(enabledFeatures).forEach(([field, value]) => {
      promises.push(
        this.sendEvent({
          namespace: "rubyLsp.enabledFeatures",
          field,
          value: value.toString(),
        }),
      );
    });

    await Promise.all(promises);

    this.context.globalState.update(
      "rubyLsp.lastConfigurationTelemetry",
      Date.now(),
    );
  }

  async sendCodeLensEvent(type: CodeLensEvent["type"]) {
    await this.sendEvent({ type, lspVersion: this.serverVersion! });
  }

  private async initialize(): Promise<boolean> {
    try {
      if (!this.api) {
        this.api = await vscode.commands.executeCommand(
          "ruby-lsp.getPrivateTelemetryApi",
        );
      }

      return Boolean(this.api);
    } catch (_error) {
      // Do nothing if no telemetry api is available
      return false;
    }
  }
}
