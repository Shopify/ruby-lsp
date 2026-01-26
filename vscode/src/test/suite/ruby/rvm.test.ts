import assert from "assert";
import path from "path";
import os from "os";

import * as vscode from "vscode";
import sinon from "sinon";
import { afterEach, beforeEach } from "mocha";

import { Rvm } from "../../../ruby/rvm";
import { WorkspaceChannel } from "../../../workspaceChannel";
import * as common from "../../../common";
import { ACTIVATION_SEPARATOR, FIELD_SEPARATOR, VALUE_SEPARATOR } from "../../../ruby/versionManager";
import { createContext, FakeContext } from "../helpers";

suite("RVM", () => {
  if (common.isWindows()) {
    // eslint-disable-next-line no-console
    console.log("Skipping RVM tests on Windows");
    return;
  }

  let context: FakeContext;
  let activationPath: vscode.Uri;
  let sandbox: sinon.SinonSandbox;

  beforeEach(() => {
    sandbox = sinon.createSandbox();
    context = createContext();
    activationPath = vscode.Uri.joinPath(context.extensionUri, "activation.rb");
  });

  afterEach(() => {
    sandbox.restore();
    context.dispose();
  });

  test("Populates the gem env and path", async () => {
    const workspacePath = process.env.PWD!;
    const workspaceFolder = {
      uri: vscode.Uri.from({ scheme: "file", path: workspacePath }),
      name: path.basename(workspacePath),
      index: 0,
    };
    const outputChannel = new WorkspaceChannel("fake", common.LOG_CHANNEL);
    const rvm = new Rvm(workspaceFolder, outputChannel, context, async () => {});

    const installationPathStub = sandbox
      .stub(rvm, "findRvmInstallation")
      .resolves(common.pathToUri(os.homedir(), ".rvm", "bin", "rvm-auto-ruby"));

    const envStub = ["3.0.0", "/path/to/gems", "true", `ANY${VALUE_SEPARATOR}true`].join(FIELD_SEPARATOR);

    const execStub = sandbox.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: `${ACTIVATION_SEPARATOR}${envStub}${ACTIVATION_SEPARATOR}`,
    });

    const { env, version, yjit } = await rvm.activate();

    assert.ok(
      execStub.calledOnceWithExactly(
        `${path.join(os.homedir(), ".rvm", "bin", "rvm-auto-ruby")} -EUTF-8:UTF-8 '${activationPath.fsPath}'`,
        {
          cwd: workspacePath,
          shell: vscode.env.shell,
          env: process.env,
          encoding: "utf-8",
        },
      ),
    );

    assert.strictEqual(version, "3.0.0");
    assert.strictEqual(yjit, true);
    assert.deepStrictEqual(env.ANY, "true");

    execStub.restore();
    installationPathStub.restore();
  });
});
