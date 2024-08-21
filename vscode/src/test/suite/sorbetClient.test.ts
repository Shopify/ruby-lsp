/* eslint-disable no-process-env */
import assert from "assert";
import path from "path";
import os from "os";
import fs from "fs";

import * as vscode from "vscode";
import { State } from "vscode-languageclient/node";
import { after, afterEach, before } from "mocha";

import { Ruby, ManagerIdentifier } from "../../ruby";
import {
  SorbetWorkspaceChannel,
  WorkspaceChannel,
} from "../../workspaceChannel";
import { RUBY_VERSION } from "../rubyVersion";
import SorbetClient from "../../sorbet";

const [major, minor, _patch] = RUBY_VERSION.split(".");

class FakeLogger {
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

async function launchClient(workspaceUri: vscode.Uri) {
  const workspaceFolder: vscode.WorkspaceFolder = {
    uri: workspaceUri,
    name: path.basename(workspaceUri.fsPath),
    index: 0,
  };

  const context = {
    extensionMode: vscode.ExtensionMode.Test,
    subscriptions: [],
    workspaceState: {
      get: (_name: string) => undefined,
      update: (_name: string, _value: any) => Promise.resolve(),
    },
  } as unknown as vscode.ExtensionContext;
  const fakeLogger = new FakeLogger();
  const outputChannel = new WorkspaceChannel("fake", fakeLogger as any);

  // Ensure that we're activating the correct Ruby version on CI
  if (process.env.CI) {
    if (os.platform() === "linux") {
      await vscode.workspace
        .getConfiguration("rubyLsp")
        .update(
          "rubyVersionManager",
          { identifier: ManagerIdentifier.Chruby },
          true,
        );

      fs.mkdirSync(path.join(os.homedir(), ".rubies"), { recursive: true });
      fs.symlinkSync(
        `/opt/hostedtoolcache/Ruby/${RUBY_VERSION}/x64`,
        path.join(os.homedir(), ".rubies", RUBY_VERSION),
      );
    } else if (os.platform() === "darwin") {
      await vscode.workspace
        .getConfiguration("rubyLsp")
        .update(
          "rubyVersionManager",
          { identifier: ManagerIdentifier.Chruby },
          true,
        );

      fs.mkdirSync(path.join(os.homedir(), ".rubies"), { recursive: true });
      fs.symlinkSync(
        `/Users/runner/hostedtoolcache/Ruby/${RUBY_VERSION}/arm64`,
        path.join(os.homedir(), ".rubies", RUBY_VERSION),
      );
    } else {
      await vscode.workspace
        .getConfiguration("rubyLsp")
        .update(
          "rubyVersionManager",
          { identifier: ManagerIdentifier.RubyInstaller },
          true,
        );

      fs.symlinkSync(
        path.join(
          "C:",
          "hostedtoolcache",
          "windows",
          "Ruby",
          RUBY_VERSION,
          "x64",
        ),
        path.join("C:", `Ruby${major}${minor}-${os.arch()}`),
      );
    }
  }

  const ruby = new Ruby(context, workspaceFolder, outputChannel);
  await ruby.activateRuby();

  const client = new SorbetClient(
    ruby,
    workspaceFolder,
    new SorbetWorkspaceChannel("fake", fakeLogger as any),
    ["exec", "srb", "tc", "--lsp", "--disable-watchman"],
  );

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

  return client;
}

suite("SorbetClient", () => {
  const workspacePath = path.dirname(
    path.dirname(path.dirname(path.dirname(__dirname))),
  );
  const workspaceUri = vscode.Uri.file(workspacePath);
  const documentUri = vscode.Uri.joinPath(
    workspaceUri,
    "lib",
    "ruby_lsp",
    "server.rb",
  );
  let client: SorbetClient;

  before(async function () {
    // 60000 should be plenty but we're seeing timeouts on Windows in CI

    // eslint-disable-next-line no-invalid-this
    this.timeout(90000);
    client = await launchClient(workspaceUri);
  });

  after(async function () {
    // eslint-disable-next-line no-invalid-this
    this.timeout(20000);

    try {
      await client.stop();
      await client.dispose();
    } catch (error: any) {
      assert.fail(`Failed to stop server: ${error.message}`);
    }

    if (process.env.CI) {
      if (os.platform() === "linux" || os.platform() === "darwin") {
        fs.rmSync(path.join(os.homedir(), ".rubies"), {
          recursive: true,
          force: true,
        });
      } else {
        fs.rmSync(path.join("C:", `Ruby${major}${minor}-${os.arch()}`), {
          recursive: true,
          force: true,
        });
      }
    }
  });

  afterEach(async () => {
    await client.sendNotification("textDocument/didClose", {
      textDocument: {
        uri: documentUri.toString(),
      },
    });
  });

  test("hover", async () => {
    const text = await vscode.workspace.fs.readFile(documentUri);

    await client.sendNotification("textDocument/didOpen", {
      textDocument: {
        uri: documentUri.toString(),
        version: 1,
        text,
      },
    });

    const response: vscode.Hover = await client.sendRequest(
      "textDocument/hover",
      {
        textDocument: {
          uri: documentUri.toString(),
        },
        position: {
          line: 3,
          character: 7,
        },
      },
    );

    assert.match((response.contents as any).value, /T.class_of\(RubyLsp\)/);
  }).timeout(20000);
});
