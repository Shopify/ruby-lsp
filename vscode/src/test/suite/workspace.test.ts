/* eslint-disable no-process-env */
import assert from "assert";
import path from "path";
import os from "os";
import fs from "fs";

import sinon from "sinon";
import * as vscode from "vscode";
import { beforeEach, afterEach } from "mocha";

import { Workspace } from "../../workspace";

import { FAKE_TELEMETRY } from "./fakeTelemetry";

suite("Workspace", () => {
  const context = {
    extensionMode: vscode.ExtensionMode.Test,
    subscriptions: [],
    workspaceState: {
      get: (_name: string) => undefined,
      update: (_name: string, _value: any) => Promise.resolve(),
    },
  } as unknown as vscode.ExtensionContext;
  let workspacePath: string;
  let workspaceUri: vscode.Uri;
  let workspaceFolder: vscode.WorkspaceFolder;
  let sandbox: sinon.SinonSandbox;
  let workspace: Workspace;

  beforeEach(() => {
    sandbox = sinon.createSandbox();
    workspacePath = fs.mkdtempSync(
      path.join(os.tmpdir(), "ruby-lsp-test-workspace-"),
    );
    workspaceUri = vscode.Uri.file(workspacePath);

    workspaceFolder = {
      uri: workspaceUri,
      name: path.basename(workspacePath),
      index: 0,
    };

    workspace = new Workspace(
      context,
      workspaceFolder,
      FAKE_TELEMETRY,
      () => {},
      new Map(),
    );
  });

  afterEach(() => {
    sandbox.restore();
    fs.rmSync(workspacePath, { recursive: true, force: true });
  });

  test("repeated rebase steps don't trigger multiple restarts", async () => {
    const gitDir = path.join(workspacePath, ".git");
    fs.mkdirSync(gitDir);

    const startStub = sandbox.stub(workspace, "start");
    const restartSpy = sandbox.spy(workspace, "restart");
    await workspace.activate();

    for (let i = 0; i < 4; i++) {
      await new Promise((resolve) => setTimeout(resolve, 50));
      fs.writeFileSync(path.join(gitDir, "rebase-apply"), "1");
      await new Promise((resolve) => setTimeout(resolve, 50));
      fs.rmSync(path.join(gitDir, "rebase-apply"));
    }

    // Give enough time for all watchers to fire and all debounces to run off
    await new Promise((resolve) => setTimeout(resolve, 10000));

    // The start call only happens once because of the inhibitRestart flag
    assert.strictEqual(startStub.callCount, 1);
    // The restart call only happens once because of the debounce
    assert.strictEqual(restartSpy.callCount, 1);
  }).timeout(60000);

  test("does not restart when watched files are touched without modifying contents", async () => {
    const lockfileUri = vscode.Uri.file(
      path.join(workspacePath, "Gemfile.lock"),
    );
    const contents = Buffer.from("hello");
    await vscode.workspace.fs.writeFile(lockfileUri, contents);

    await workspace.activate();

    const startStub = sandbox.stub(workspace, "start");
    const restartSpy = sandbox.spy(workspace, "restart");

    for (let i = 0; i < 4; i++) {
      const updateDate = new Date();
      fs.utimesSync(lockfileUri.fsPath, updateDate, updateDate);
      await new Promise((resolve) => setTimeout(resolve, 50));
    }

    // Give enough time for all watchers to fire and all debounces to run off
    await new Promise((resolve) => setTimeout(resolve, 6000));

    assert.strictEqual(startStub.callCount, 0);
    assert.strictEqual(restartSpy.callCount, 0);
  }).timeout(10000);
});
