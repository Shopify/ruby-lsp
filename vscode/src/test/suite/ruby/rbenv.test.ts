import assert from "assert";
import path from "path";
import os from "os";
import fs from "fs";

import * as vscode from "vscode";
import sinon from "sinon";

import { Rbenv } from "../../../ruby/rbenv";
import { WorkspaceChannel } from "../../../workspaceChannel";
import * as common from "../../../common";
import { ACTIVATION_SEPARATOR } from "../../../ruby/versionManager";

suite("Rbenv", () => {
  if (os.platform() === "win32") {
    // eslint-disable-next-line no-console
    console.log("Skipping Rbenv tests on Windows");
    return;
  }

  const context = {
    extensionMode: vscode.ExtensionMode.Test,
    subscriptions: [],
    workspaceState: {
      get: (_name: string) => undefined,
      update: (_name: string, _value: any) => Promise.resolve(),
    },
    extensionUri: vscode.Uri.parse("file:///fake"),
  } as unknown as vscode.ExtensionContext;

  test("Finds Ruby based on .ruby-version", async () => {
    // eslint-disable-next-line no-process-env
    const workspacePath = process.env.PWD!;
    const workspaceFolder = {
      uri: vscode.Uri.from({ scheme: "file", path: workspacePath }),
      name: path.basename(workspacePath),
      index: 0,
    };
    const outputChannel = new WorkspaceChannel("fake", common.LOG_CHANNEL);
    const rbenv = new Rbenv(
      workspaceFolder,
      outputChannel,
      context,
      async () => {},
    );

    const envStub = {
      env: { ANY: "true" },
      yjit: true,
      version: "3.0.0",
    };

    const execStub = sinon.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: `${ACTIVATION_SEPARATOR}${JSON.stringify(envStub)}${ACTIVATION_SEPARATOR}`,
    });

    const { env, version, yjit } = await rbenv.activate();

    assert.ok(
      execStub.calledOnceWithExactly(
        `rbenv exec ruby -W0 -rjson '/fake/activation.rb'`,
        {
          cwd: workspacePath,
          shell: vscode.env.shell,
          // eslint-disable-next-line no-process-env
          env: process.env,
        },
      ),
    );

    assert.strictEqual(version, "3.0.0");
    assert.strictEqual(yjit, true);
    assert.strictEqual(env.ANY, "true");
    execStub.restore();
  });

  test("Allows configuring where rbenv is installed", async () => {
    const workspacePath = fs.mkdtempSync(
      path.join(os.tmpdir(), "ruby-lsp-test-"),
    );
    const workspaceFolder = {
      uri: vscode.Uri.from({ scheme: "file", path: workspacePath }),
      name: path.basename(workspacePath),
      index: 0,
    };
    const outputChannel = new WorkspaceChannel("fake", common.LOG_CHANNEL);
    const rbenv = new Rbenv(
      workspaceFolder,
      outputChannel,
      context,
      async () => {},
    );

    const envStub = {
      env: { ANY: "true" },
      yjit: true,
      version: "3.0.0",
    };

    const execStub = sinon.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: `${ACTIVATION_SEPARATOR}${JSON.stringify(envStub)}${ACTIVATION_SEPARATOR}`,
    });

    const rbenvPath = path.join(workspacePath, "rbenv");
    fs.writeFileSync(rbenvPath, "fakeRbenvBinary");

    const configStub = sinon
      .stub(vscode.workspace, "getConfiguration")
      .returns({
        get: (name: string) => {
          if (name === "rubyVersionManager.rbenvExecutablePath") {
            return rbenvPath;
          }
          return "";
        },
      } as any);

    const { env, version, yjit } = await rbenv.activate();

    assert.ok(
      execStub.calledOnceWithExactly(
        `${rbenvPath} exec ruby -W0 -rjson '/fake/activation.rb'`,
        {
          cwd: workspacePath,
          shell: vscode.env.shell,
          // eslint-disable-next-line no-process-env
          env: process.env,
        },
      ),
    );

    assert.strictEqual(version, "3.0.0");
    assert.strictEqual(yjit, true);
    assert.deepStrictEqual(env.ANY, "true");

    execStub.restore();
    configStub.restore();
    fs.rmSync(workspacePath, { recursive: true, force: true });
  });

  test("Reports invalid JSON environments", async () => {
    // eslint-disable-next-line no-process-env
    const workspacePath = process.env.PWD!;
    const workspaceFolder = {
      uri: vscode.Uri.from({ scheme: "file", path: workspacePath }),
      name: path.basename(workspacePath),
      index: 0,
    };
    const outputChannel = new WorkspaceChannel("fake", common.LOG_CHANNEL);
    const rbenv = new Rbenv(
      workspaceFolder,
      outputChannel,
      context,
      async () => {},
    );

    const execStub = sinon.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: `${ACTIVATION_SEPARATOR}not a json${ACTIVATION_SEPARATOR}`,
    });

    const errorStub = sinon.stub(outputChannel, "error");

    await assert.rejects(
      rbenv.activate(),
      "SyntaxError: Unexpected token 'o', \"not a json\" is not valid JSON",
    );

    assert.ok(
      execStub.calledOnceWithExactly(
        `rbenv exec ruby -W0 -rjson '/fake/activation.rb'`,
        {
          cwd: workspacePath,
          shell: vscode.env.shell,
          // eslint-disable-next-line no-process-env
          env: process.env,
        },
      ),
    );

    assert.ok(
      errorStub.calledOnceWithExactly(
        "Tried parsing invalid JSON environment: not a json",
      ),
    );

    execStub.restore();
    errorStub.restore();
  });
});
