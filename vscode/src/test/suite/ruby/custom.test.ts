import assert from "assert";
import path from "path";
import fs from "fs";
import os from "os";

import * as vscode from "vscode";
import sinon from "sinon";

import { Custom } from "../../../ruby/custom";
import { WorkspaceChannel } from "../../../workspaceChannel";
import * as common from "../../../common";
import {
  ACTIVATION_SEPARATOR,
  FIELD_SEPARATOR,
  VALUE_SEPARATOR,
} from "../../../ruby/versionManager";

suite("Custom", () => {
  const context = {
    extensionMode: vscode.ExtensionMode.Test,
    subscriptions: [],
    workspaceState: {
      get: (_name: string) => undefined,
      update: (_name: string, _value: any) => Promise.resolve(),
    },
    extensionUri: vscode.Uri.parse("file:///fake"),
  } as unknown as vscode.ExtensionContext;

  test("Invokes custom script and then Ruby", async () => {
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
    const custom = new Custom(
      workspaceFolder,
      outputChannel,
      context,
      async () => {},
    );

    const envStub = [
      "3.0.0",
      "/path/to/gems",
      "true",
      `ANY${VALUE_SEPARATOR}true`,
    ].join(FIELD_SEPARATOR);

    const execStub = sinon.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: `${ACTIVATION_SEPARATOR}${envStub}${ACTIVATION_SEPARATOR}`,
    });

    const commandStub = sinon
      .stub(custom, "customCommand")
      .returns("my_version_manager activate_env");
    const { env, version, yjit } = await custom.activate();
    const activationUri = vscode.Uri.joinPath(
      context.extensionUri,
      "activation.rb",
    );

    // We must not set the shell on Windows
    const shell = os.platform() === "win32" ? undefined : vscode.env.shell;

    assert.ok(
      execStub.calledOnceWithExactly(
        `my_version_manager activate_env && ruby -EUTF-8:UTF-8 '${activationUri.fsPath}'`,
        {
          cwd: uri.fsPath,
          shell,
          // eslint-disable-next-line no-process-env
          env: process.env,
          encoding: "utf-8",
        },
      ),
    );

    assert.strictEqual(version, "3.0.0");
    assert.strictEqual(yjit, true);
    assert.deepStrictEqual(env.ANY, "true");

    execStub.restore();
    commandStub.restore();
    fs.rmSync(workspacePath, { recursive: true, force: true });
  });
});
