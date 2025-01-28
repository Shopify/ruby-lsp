/* eslint-disable no-process-env */
import path from "path";
import assert from "assert";
import fs from "fs";
import os from "os";

import sinon from "sinon";
import * as vscode from "vscode";
import { beforeEach, afterEach } from "mocha";

import { RubyLsp } from "../../rubyLsp";
import { RUBY_VERSION } from "../rubyVersion";
import { ManagerIdentifier } from "../../ruby";

import { FAKE_TELEMETRY } from "./fakeTelemetry";
import { createRubySymlinks, fakeContext } from "./helpers";

suite("Ruby LSP", () => {
  const context = fakeContext();
  let workspacePath: string;
  let workspaceUri: vscode.Uri;
  let workspaceFolder: vscode.WorkspaceFolder;
  const originalSaveBeforeStart = vscode.workspace
    .getConfiguration("debug")
    .get("saveBeforeStart");
  let workspacesStub: sinon.SinonStub;

  beforeEach(async () => {
    await vscode.workspace
      .getConfiguration("debug")
      .update("saveBeforeStart", "none", true);
    workspacePath = fs.mkdtempSync(
      path.join(os.tmpdir(), "ruby-lsp-integration-test-"),
    );
    workspaceUri = vscode.Uri.file(workspacePath);
    workspaceFolder = {
      uri: workspaceUri,
      name: path.basename(workspacePath),
      index: 0,
    };

    workspacesStub = sinon
      .stub(vscode.workspace, "workspaceFolders")
      .get(() => [workspaceFolder]);

    if (process.env.CI) {
      createRubySymlinks();
    }
  });

  afterEach(async () => {
    workspacesStub.restore();
    fs.rmSync(workspacePath, { recursive: true, force: true });

    await vscode.workspace
      .getConfiguration("debug")
      .update("saveBeforeStart", originalSaveBeforeStart, true);
  });

  function writeFileSetup() {
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
  }

  test("launching debugger in a project with local Bundler settings and composed bundle", async () => {
    writeFileSetup();

    if (process.env.CI) {
      const manager =
        os.platform() === "win32"
          ? ManagerIdentifier.RubyInstaller
          : ManagerIdentifier.Chruby;

      await vscode.workspace
        .getConfiguration("rubyLsp")
        .update("rubyVersionManager", { identifier: manager }, true);
    }

    const rubyLsp = new RubyLsp(context, FAKE_TELEMETRY);

    try {
      await rubyLsp.activate();
    } catch (error: any) {
      assert.fail(
        `Failed to activate Ruby LSP: ${error.message}\n\n${error.stack}`,
      );
    }

    // Verify that the composed environment was properly merged into the Ruby object
    const workspace = rubyLsp.getWorkspace(workspaceFolder.uri)!;
    assert.match(workspace.ruby.env.BUNDLE_PATH!, /vendor(\/|\\)bundle/);
    assert.match(
      workspace.ruby.env.BUNDLE_GEMFILE!,
      /\.ruby-lsp(\/|\\)Gemfile/,
    );

    try {
      await vscode.debug.startDebugging(workspaceFolder, {
        type: "ruby_lsp",
        name: "Debug",
        request: "launch",
        program: `ruby ${path.join(workspacePath, "test.rb")}`,
        workspaceFolder,
      });
    } catch (error: any) {
      assert.fail(`Failed to launch debugger: ${error.message}`);
    }

    await new Promise<void>((resolve) => {
      const callback = vscode.debug.onDidTerminateDebugSession((_session) => {
        context.subscriptions.forEach((subscription) => {
          if (!("logLevel" in subscription)) {
            subscription.dispose();
          }
        });

        callback.dispose();
        resolve();
      });
    });
  }).timeout(90000);
});
