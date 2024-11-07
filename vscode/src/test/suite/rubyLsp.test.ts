import path from "path";
import assert from "assert";
import fs from "fs";
import os from "os";

import sinon from "sinon";
import * as vscode from "vscode";
import { beforeEach, afterEach, before, after } from "mocha";
import { State } from "vscode-languageclient";

import { RubyLsp } from "../../rubyLsp";
import { RUBY_VERSION } from "../rubyVersion";

import { FAKE_TELEMETRY } from "./fakeTelemetry";
import { ensureRubyInstallationPaths } from "./testHelpers";

suite("Ruby LSP", () => {
  const context = {
    extensionMode: vscode.ExtensionMode.Test,
    subscriptions: [],
    workspaceState: {
      get: (_name: string) => undefined,
      update: (_name: string, _value: any) => Promise.resolve(),
    },
    extensionUri: vscode.Uri.file(
      path.dirname(path.dirname(path.dirname(__dirname))),
    ),
  } as unknown as vscode.ExtensionContext;
  let workspacePath: string;
  let workspaceUri: vscode.Uri;
  let workspaceFolder: vscode.WorkspaceFolder;
  const originalSaveBeforeStart = vscode.workspace
    .getConfiguration("debug")
    .get("saveBeforeStart");

  before(async () => {
    await vscode.workspace
      .getConfiguration("debug")
      .update("saveBeforeStart", "none", true);
  });

  after(async () => {
    await vscode.workspace
      .getConfiguration("debug")
      .update("saveBeforeStart", originalSaveBeforeStart, true);
  });

  beforeEach(() => {
    workspacePath = fs.mkdtempSync(
      path.join(os.tmpdir(), "ruby-lsp-integration-test-"),
    );
    workspaceUri = vscode.Uri.file(workspacePath);
    workspaceFolder = {
      uri: workspaceUri,
      name: path.basename(workspacePath),
      index: 0,
    };
  });

  afterEach(() => {
    fs.rmSync(workspacePath, { recursive: true, force: true });
  });

  test("launching debugger in a project with local Bundler settings and composed bundle", async () => {
    fs.writeFileSync(path.join(workspacePath, "test.rb"), "1 + 1");
    fs.writeFileSync(path.join(workspacePath, ".ruby-version"), RUBY_VERSION);
    fs.writeFileSync(
      path.join(workspacePath, "Gemfile"),
      'source "https://rubygems.org"\n',
    );
    fs.writeFileSync(
      path.join(workspacePath, "Gemfile.lock"),
      [
        "GEM",
        "  remote: https://rubygems.org/",
        "  specs:",
        "",
        "PLATFORMS",
        "  arm64-darwin-23",
        "  ruby",
        "",
        "DEPENDENCIES",
        "",
        "BUNDLED WITH",
        "  2.5.16",
      ].join("\n"),
    );
    fs.mkdirSync(path.join(workspacePath, ".bundle"));
    fs.writeFileSync(
      path.join(workspacePath, ".bundle", "config"),
      `BUNDLE_PATH: ${path.join("vendor", "bundle")}`,
    );

    await ensureRubyInstallationPaths();

    const rubyLsp = new RubyLsp(context, FAKE_TELEMETRY);

    try {
      await rubyLsp.activate(workspaceFolder);

      const client = rubyLsp.workspaces.get(
        workspaceFolder.uri.toString(),
      )!.lspClient!;

      if (client.state !== State.Running) {
        await new Promise<void>((resolve) => {
          const callback = client.onDidChangeState(() => {
            if (client.state === State.Running) {
              callback.dispose();
              resolve();
            }
          });
        });
      }
    } catch (error: any) {
      assert.fail(
        `Failed to activate Ruby LSP: ${error.message}\n\n${error.stack}`,
      );
    }

    const stub = sinon.stub(vscode.window, "activeTextEditor").get(() => {
      return {
        document: {
          uri: vscode.Uri.file(path.join(workspacePath, "test.rb")),
        },
      } as vscode.TextEditor;
    });

    const getWorkspaceStub = sinon
      .stub(vscode.workspace, "getWorkspaceFolder")
      .returns(workspaceFolder);

    try {
      await vscode.debug.startDebugging(workspaceFolder, {
        type: "ruby_lsp",
        name: "Debug",
        request: "launch",
        program: `ruby ${path.join(workspacePath, "test.rb")}`,
      });
    } catch (error: any) {
      assert.fail(`Failed to launch debugger: ${error.message}`);
    }

    // The debugger might take a bit of time to disconnect from the editor. We need to perform cleanup when we receive
    // the termination callback or else we try to dispose of the debugger client too early, but we need to wait for that
    // so that we can clean up stubs otherwise they leak into other tests.
    await new Promise<void>((resolve) => {
      vscode.debug.onDidTerminateDebugSession((_session) => {
        stub.restore();
        getWorkspaceStub.restore();

        context.subscriptions.forEach((subscription) => {
          if (!("logLevel" in subscription)) {
            subscription.dispose();
          }
        });

        resolve();
      });
    });
  }).timeout(90000);
});
