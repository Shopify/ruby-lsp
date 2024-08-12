import * as vscode from "vscode";

class FakeSender implements vscode.TelemetrySender {
  public receivedEvents: any[];
  public receivedErrors: any[];

  constructor() {
    this.receivedEvents = [];
    this.receivedErrors = [];
  }

  sendEventData(
    eventName: string,
    data?: Record<string, any> | undefined,
  ): void {
    this.receivedEvents.push({ eventName, data });
  }

  sendErrorData(error: Error, data?: Record<string, any> | undefined): void {
    this.receivedErrors.push({ error, data });
  }
}

export const FAKE_TELEMETRY = vscode.env.createTelemetryLogger(
  new FakeSender(),
  {
    ignoreUnhandledErrors: true,
  },
);
