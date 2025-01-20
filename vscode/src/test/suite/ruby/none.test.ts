import assert from "assert";
import path from "path";
import fs from "fs";
import os from "os";

import * as vscode from "vscode";
import sinon from "sinon";

import { None } from "../../../ruby/none";
import { WorkspaceChannel } from "../../../workspaceChannel";
import * as common from "../../../common";
import { ACTIVATION_SEPARATOR } from "../../../ruby/versionManager";

suite("None", () => {
  test("Invokes Ruby directly", async () => {
    const context = {
      extensionMode: vscode.ExtensionMode.Test,
      subscriptions: [],
      workspaceState: {
        get: (_name: string) => undefined,
        update: (_name: string, _value: any) => Promise.resolve(),
      },
      extensionUri: vscode.Uri.parse("file:///fake"),
    } as unknown as vscode.ExtensionContext;
    const workspacePath = fs.mkdtempSync(
      path.join(os.tmpdir(), "ruby-lsp-test-"),
    );
    const uri = vscode.Uri.file(workspacePath);
    const workspaceFolder = {
      uri,
      name: path.basename(workspacePath),
      index: 0,
    };
    const outputChannel = new WorkspaceChannel("fake", common.LOG_CHANNEL);
    const none = new None(
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

    const { env, version, yjit } = await none.activate();
    const activationUri = vscode.Uri.joinPath(
      context.extensionUri,
      "activation.rb",
    );

    // We must not set the shell on Windows
    const shell = os.platform() === "win32" ? undefined : vscode.env.shell;

    assert.ok(
<<<<<<< Updated upstream
      execStub.calledOnceWithExactly(`ruby -W0 -rjson '/fake/activation.rb'`, {
=======
      execStub.calledOnceWithExactly(`ruby '${activationUri.fsPath}'`, {
>>>>>>> Stashed changes
        cwd: uri.fsPath,
        shell,
        // eslint-disable-next-line no-process-env
        env: process.env,
      }),
    );

    assert.strictEqual(version, "3.0.0");
    assert.strictEqual(yjit, true);
    assert.deepStrictEqual(env.ANY, "true");

    execStub.restore();
    fs.rmSync(workspacePath, { recursive: true, force: true });
  });
});
