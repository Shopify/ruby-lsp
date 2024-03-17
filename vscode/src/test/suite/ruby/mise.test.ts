import assert from "assert";
import path from "path";
import os from "os";

import * as vscode from "vscode";
import sinon from "sinon";

import { Mise } from "../../../ruby/mise";
import { WorkspaceChannel } from "../../../workspaceChannel";
import * as common from "../../../common";

suite("Mise", () => {
  if (os.platform() === "win32") {
    // eslint-disable-next-line no-console
    console.log("Skipping Mise tests on Windows");
    return;
  }

  test("Finds mise binary in default install location", async () => {
    // eslint-disable-next-line no-process-env
    const workspacePath = process.env.PWD!;
    const workspaceFolder = {
      uri: vscode.Uri.from({ scheme: "file", path: workspacePath }),
      name: path.basename(workspacePath),
      index: 0,
    };
    const outputChannel = new WorkspaceChannel("fake", common.LOG_CHANNEL);
    const mise = new Mise(workspaceFolder, outputChannel);

    const activationScript =
      "STDERR.print({ env: ENV.to_h, yjit: !!defined?(RubyVM::YJIT), version: RUBY_VERSION }.to_json)";

    const execStub = sinon.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: JSON.stringify({
        env: { ANY: "true" },
        yjit: true,
        version: "3.0.0",
      }),
    });

    const { env, version, yjit } = await mise.activate();

    assert.ok(
      execStub.calledOnceWithExactly(
        `${os.homedir()}/.local/bin/mise x -- ruby -W0 -rjson -e '${activationScript}'`,
        { cwd: workspacePath },
      ),
    );

    assert.strictEqual(version, "3.0.0");
    assert.strictEqual(yjit, true);
    assert.deepStrictEqual(env.ANY, "true");

    execStub.restore();
  });

  test("Finds mise binary in homebrew install location", async () => {
    if (os.platform() !== "darwin") {
      // eslint-disable-next-line no-console
      console.log("Skipping Mise test on non-windows");
      return;
    }
    // eslint-disable-next-line no-process-env
    const workspacePath = process.env.PWD!;
    const workspaceFolder = {
      uri: vscode.Uri.from({ scheme: "file", path: workspacePath }),
      name: path.basename(workspacePath),
      index: 0,
    };
    const outputChannel = new WorkspaceChannel("fake", common.LOG_CHANNEL);
    const mise = new Mise(workspaceFolder, outputChannel);

    const activationScript =
      "STDERR.print({ env: ENV.to_h, yjit: !!defined?(RubyVM::YJIT), version: RUBY_VERSION }.to_json)";

    const execStub = sinon.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: JSON.stringify({
        env: { ANY: "true" },
        yjit: true,
        version: "3.0.0",
      }),
    });

    // pretend that the default mise install location doesn't exist
    const statStub = sinon
      .stub(vscode.workspace.fs, "stat")
      .rejects()
      .onFirstCall();

    const { env, version, yjit } = await mise.activate();

    assert.ok(
      execStub.calledOnceWithExactly(
        `/opt/homebrew/bin/mise x -- ruby -W0 -rjson -e '${activationScript}'`,
        { cwd: workspacePath },
      ),
    );

    assert.strictEqual(version, "3.0.0");
    assert.strictEqual(yjit, true);
    assert.deepStrictEqual(env.ANY, "true");

    execStub.restore();
    statStub.restore();
  });
});
