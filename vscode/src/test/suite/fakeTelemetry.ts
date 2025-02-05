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

export class FakeLogger {
  receivedMessages = "";

  trace(message: string, ..._args: any[]): void {
    this.receivedMessages += message;
  }

  debug(message: string, ..._args: any[]): void {
    this.receivedMessages += message;
  }

  info(message: string, ..._args: any[]): void {
    this.receivedMessages += message;
  }

  warn(message: string, ..._args: any[]): void {
    this.receivedMessages += message;
  }

  error(error: string | Error, ..._args: any[]): void {
    this.receivedMessages += error.toString();
  }

  append(value: string): void {
    this.receivedMessages += value;
  }

  appendLine(value: string): void {
    this.receivedMessages += value;
  }
}
