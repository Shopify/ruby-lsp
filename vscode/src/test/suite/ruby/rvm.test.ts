/* eslint-disable no-process-env */
import assert from "assert";
import path from "path";
import os from "os";

import * as vscode from "vscode";
import sinon from "sinon";

import { Rvm } from "../../../ruby/rvm";
import { WorkspaceChannel } from "../../../workspaceChannel";
import * as common from "../../../common";

suite("RVM", () => {
  if (os.platform() === "win32") {
    // eslint-disable-next-line no-console
    console.log("Skipping RVM tests on Windows");
    return;
  }

  test("Populates the gem env and path", async () => {
    const workspacePath = process.env.PWD!;
    const workspaceFolder = {
      uri: vscode.Uri.from({ scheme: "file", path: workspacePath }),
      name: path.basename(workspacePath),
      index: 0,
    };
    const outputChannel = new WorkspaceChannel("fake", common.LOG_CHANNEL);
    const rvm = new Rvm(workspaceFolder, outputChannel);

    const activationScript =
      "STDERR.print({ env: ENV.to_h, yjit: !!defined?(RubyVM::YJIT), version: RUBY_VERSION }.to_json)";

    const installationPathStub = sinon
      .stub(rvm, "findRvmInstallation")
      .resolves(
        vscode.Uri.joinPath(
          vscode.Uri.file(os.homedir()),
          ".rvm",
          "bin",
          "rvm-auto-ruby",
        ),
      );

    const execStub = sinon.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: JSON.stringify({
        env: {
          ANY: "true",
        },
        yjit: true,
        version: "3.0.0",
      }),
    });

    const { env, version, yjit } = await rvm.activate();

    assert.ok(
      execStub.calledOnceWithExactly(
        `${path.join(os.homedir(), ".rvm", "bin", "rvm-auto-ruby")} -W0 -rjson -e '${activationScript}'`,
        { cwd: workspacePath },
      ),
    );

    assert.strictEqual(version, "3.0.0");
    assert.strictEqual(yjit, true);
    assert.deepStrictEqual(env.ANY, "true");

    execStub.restore();
    installationPathStub.restore();
  });
});
