import assert from "assert";
import path from "path";
import os from "os";

import * as vscode from "vscode";
import sinon from "sinon";

import { Rbenv } from "../../../ruby/rbenv";
import { WorkspaceChannel } from "../../../workspaceChannel";
import * as common from "../../../common";

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

    const activationScript =
      "STDERR.print({env: ENV.to_h,yjit:!!defined?(RubyVM::YJIT),version:RUBY_VERSION}.to_json)";

    const execStub = sinon.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: JSON.stringify({
        env: { ANY: "true" },
        yjit: true,
        version: "3.0.0",
      }),
    });

    const { env, version, yjit } = await rbenv.activate();

    assert.ok(
      execStub.calledOnceWithExactly(
        `rbenv exec ruby -W0 -rjson -e '${activationScript}'`,
        { cwd: workspacePath },
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

    const activationScript =
      "STDERR.print({env: ENV.to_h,yjit:!!defined?(RubyVM::YJIT),version:RUBY_VERSION}.to_json)";

    const execStub = sinon.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: "not a json",
    });

    const errorStub = sinon.stub(outputChannel, "error");

    await assert.rejects(
      rbenv.activate(),
      "SyntaxError: Unexpected token 'o', \"not a json\" is not valid JSON",
    );

    assert.ok(
      execStub.calledOnceWithExactly(
        `rbenv exec ruby -W0 -rjson -e '${activationScript}'`,
        { cwd: workspacePath },
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
