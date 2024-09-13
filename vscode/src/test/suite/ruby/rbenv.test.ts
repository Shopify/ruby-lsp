import assert from "assert";
import path from "path";
import os from "os";

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

  test("Finds Ruby based on .ruby-version", async () => {
    // eslint-disable-next-line no-process-env
    const workspacePath = process.env.PWD!;
    const workspaceFolder = {
      uri: vscode.Uri.from({ scheme: "file", path: workspacePath }),
      name: path.basename(workspacePath),
      index: 0,
    };
    const outputChannel = new WorkspaceChannel("fake", common.LOG_CHANNEL);
    const rbenv = new Rbenv(workspaceFolder, outputChannel);

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
        `rbenv exec ruby -W0 -rjson -e '${rbenv.activationScript}'`,
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

  test("Reports invalid JSON environments", async () => {
    // eslint-disable-next-line no-process-env
    const workspacePath = process.env.PWD!;
    const workspaceFolder = {
      uri: vscode.Uri.from({ scheme: "file", path: workspacePath }),
      name: path.basename(workspacePath),
      index: 0,
    };
    const outputChannel = new WorkspaceChannel("fake", common.LOG_CHANNEL);
    const rbenv = new Rbenv(workspaceFolder, outputChannel);

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
        `rbenv exec ruby -W0 -rjson -e '${rbenv.activationScript}'`,
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
