import * as vscode from "vscode";

export class WorkspaceChannel implements vscode.LogOutputChannel {
  public readonly onDidChangeLogLevel: vscode.Event<vscode.LogLevel>;
  private readonly actualChannel: vscode.LogOutputChannel;
  private readonly prefix: string;

  constructor(workspaceName: string, actualChannel: vscode.LogOutputChannel) {
    this.prefix = `(${workspaceName})`;
    this.actualChannel = actualChannel;
    this.onDidChangeLogLevel = this.actualChannel.onDidChangeLogLevel;
  }

  get name(): string {
    return this.actualChannel.name;
  }

  get logLevel(): vscode.LogLevel {
    return this.actualChannel.logLevel;
  }

  trace(message: string, ...args: any[]): void {
    this.actualChannel.trace(`${this.prefix} ${message}`, ...args);
  }

  debug(message: string, ...args: any[]): void {
    this.actualChannel.debug(`${this.prefix} ${message}`, ...args);
  }

  info(message: string, ...args: any[]): void {
    this.actualChannel.info(`${this.prefix} ${message}`, ...args);
  }

  warn(message: string, ...args: any[]): void {
    this.actualChannel.warn(`${this.prefix} ${message}`, ...args);
  }

  error(error: string | Error, ...args: any[]): void {
    this.actualChannel.error(`${this.prefix} ${error}`, ...args);
  }

  append(value: string): void {
    this.actualChannel.append(`${this.prefix} ${value}`);
  }

  appendLine(value: string): void {
    this.actualChannel.appendLine(`${this.prefix} ${value}`);
  }

  replace(value: string): void {
    this.actualChannel.replace(`${this.prefix} ${value}`);
  }

  clear(): void {
    this.actualChannel.clear();
  }

  show(preserveFocus?: boolean | undefined): void;
  show(
    column?: vscode.ViewColumn | undefined,
    preserveFocus?: boolean | undefined,
  ): void;

  show(_column?: unknown, preserveFocus?: boolean | undefined): void {
    this.actualChannel.show(preserveFocus);
  }

  hide(): void {
    this.actualChannel.hide();
  }

  dispose(): void {
    this.actualChannel.dispose();
  }
}
