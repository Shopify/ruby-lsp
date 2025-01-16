import os from "os";
import assert from "assert";
import path from "path";
import fs from "fs";

import * as vscode from "vscode";
import { State, WorkDoneProgress } from "vscode-languageclient";

import { MAJOR, MINOR, RUBY_VERSION } from "../rubyVersion";
import { ManagerIdentifier, Ruby } from "../../ruby";
import Client from "../../client";
import { WorkspaceChannel } from "../../workspaceChannel";

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

export async function setupRubyForCi() {
  if (os.platform() === "linux") {
    await vscode.workspace
      .getConfiguration("rubyLsp")
      .update(
        "rubyVersionManager",
        { identifier: ManagerIdentifier.Chruby },
        true,
      );

    const linkPath = path.join(os.homedir(), ".rubies", RUBY_VERSION);

    if (!fs.existsSync(linkPath)) {
      fs.mkdirSync(path.join(os.homedir(), ".rubies"), { recursive: true });
      fs.symlinkSync(`/opt/hostedtoolcache/Ruby/${RUBY_VERSION}/x64`, linkPath);
    }
  } else if (os.platform() === "darwin") {
    await vscode.workspace
      .getConfiguration("rubyLsp")
      .update(
        "rubyVersionManager",
        { identifier: ManagerIdentifier.Chruby },
        true,
      );

    const linkPath = path.join(os.homedir(), ".rubies", RUBY_VERSION);

    if (!fs.existsSync(linkPath)) {
      fs.mkdirSync(path.join(os.homedir(), ".rubies"), { recursive: true });
      fs.symlinkSync(
        `/Users/runner/hostedtoolcache/Ruby/${RUBY_VERSION}/arm64`,
        linkPath,
      );
    }
  } else {
    await vscode.workspace
      .getConfiguration("rubyLsp")
      .update(
        "rubyVersionManager",
        { identifier: ManagerIdentifier.RubyInstaller },
        true,
      );

    const linkPath = path.join("C:", `Ruby${MAJOR}${MINOR}-${os.arch()}`);

    if (!fs.existsSync(linkPath)) {
      fs.symlinkSync(
        path.join(
          "C:",
          "hostedtoolcache",
          "windows",
          "Ruby",
          RUBY_VERSION,
          "x64",
        ),
        linkPath,
      );
    }
  }
}

export async function launchClient(
  context: vscode.ExtensionContext,
  ruby: Ruby,
  workspaceFolder: vscode.WorkspaceFolder,
  outputChannel: WorkspaceChannel,
): Promise<Client> {
  const client = new Client(
    context,
    FAKE_TELEMETRY,
    ruby,
    () => {},
    workspaceFolder,
    outputChannel,
    new Map<string, string>(),
  );

  const fakeLogger = new FakeLogger();
  client.clientOptions.initializationFailedHandler = (error) => {
    assert.fail(
      `Failed to start server ${error.message}\n${fakeLogger.receivedMessages}`,
    );
  };

  try {
    await client.start();
  } catch (error: any) {
    assert.fail(`Failed to start server ${error.message}`);
  }

  assert.strictEqual(client.state, State.Running);

  await new Promise<void>((resolve) => {
    client.onProgress(
      WorkDoneProgress.type,
      "indexing-progress",
      (value: any) => {
        if (value.kind === "end") {
          resolve();
        }
      },
    );
  });

  await client.afterStart();
  return client;
}
