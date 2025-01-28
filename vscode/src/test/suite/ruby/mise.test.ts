import assert from "assert";
import path from "path";
import os from "os";
import fs from "fs";

import * as vscode from "vscode";
import sinon from "sinon";

import { Mise } from "../../../ruby/mise";
import { WorkspaceChannel } from "../../../workspaceChannel";
import * as common from "../../../common";
import {
  ACTIVATION_SEPARATOR,
  FIELD_SEPARATOR,
  VALUE_SEPARATOR,
} from "../../../ruby/versionManager";
import { fakeContext } from "../helpers";

suite("Mise", () => {
  if (os.platform() === "win32") {
    // eslint-disable-next-line no-console
    console.log("Skipping Mise tests on Windows");
    return;
  }

  const context = fakeContext();

  test("Finds Ruby only binary path is appended to PATH", async () => {
    // eslint-disable-next-line no-process-env
    const workspacePath = process.env.PWD!;
    const workspaceFolder = {
      uri: vscode.Uri.from({ scheme: "file", path: workspacePath }),
      name: path.basename(workspacePath),
      index: 0,
    };
    const outputChannel = new WorkspaceChannel("fake", common.LOG_CHANNEL);
    const mise = new Mise(
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
    const findStub = sinon
      .stub(mise, "findMiseUri")
      .resolves(
        vscode.Uri.joinPath(
          vscode.Uri.file(os.homedir()),
          ".local",
          "bin",
          "mise",
        ),
      );

    const { env, version, yjit } = await mise.activate();

    assert.ok(
      execStub.calledOnceWithExactly(
        `${os.homedir()}/.local/bin/mise x -- ruby -EUTF-8:UTF-8 '${context.extensionUri.fsPath}/activation.rb'`,
        {
          cwd: workspacePath,
          shell: vscode.env.shell,
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
    findStub.restore();
  });

  test("Allows configuring where Mise is installed", async () => {
    const workspacePath = fs.mkdtempSync(
      path.join(os.tmpdir(), "ruby-lsp-test-"),
    );
    const workspaceFolder = {
      uri: vscode.Uri.from({ scheme: "file", path: workspacePath }),
      name: path.basename(workspacePath),
      index: 0,
    };
    const outputChannel = new WorkspaceChannel("fake", common.LOG_CHANNEL);
    const mise = new Mise(
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

    const misePath = path.join(workspacePath, "mise");
    fs.writeFileSync(misePath, "fakeMiseBinary");

    const configStub = sinon
      .stub(vscode.workspace, "getConfiguration")
      .returns({
        get: (name: string) => {
          if (name === "rubyVersionManager.miseExecutablePath") {
            return misePath;
          }
          return "";
        },
      } as any);

    const { env, version, yjit } = await mise.activate();

    assert.ok(
      execStub.calledOnceWithExactly(
        `${misePath} x -- ruby -EUTF-8:UTF-8 '${context.extensionUri.fsPath}/activation.rb'`,
        {
          cwd: workspacePath,
          shell: vscode.env.shell,
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
    configStub.restore();
    fs.rmSync(workspacePath, { recursive: true, force: true });
  });
});
