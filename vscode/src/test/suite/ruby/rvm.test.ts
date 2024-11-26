/* eslint-disable no-process-env */
import assert from "assert";
import path from "path";
import os from "os";

import * as vscode from "vscode";
import sinon from "sinon";

import { Rvm } from "../../../ruby/rvm";
import { WorkspaceChannel } from "../../../workspaceChannel";
import * as common from "../../../common";
import { ACTIVATION_SEPARATOR } from "../../../ruby/versionManager";
import { createSpawnStub } from "../testHelpers";

suite("RVM", () => {
  if (os.platform() === "win32") {
    // eslint-disable-next-line no-console
    console.log("Skipping RVM tests on Windows");
    return;
  }

  let spawnStub: sinon.SinonStub;
  let stdinData: string[];

  teardown(() => {
    spawnStub?.restore();
  });

  test("Populates the gem env and path", async () => {
    const workspacePath = process.env.PWD!;
    const workspaceFolder = {
      uri: vscode.Uri.from({ scheme: "file", path: workspacePath }),
      name: path.basename(workspacePath),
      index: 0,
    };
    const outputChannel = new WorkspaceChannel("fake", common.LOG_CHANNEL);
    const rvm = new Rvm(workspaceFolder, outputChannel, async () => {});

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

    const envStub = {
      env: {
        ANY: "true",
      },
      yjit: true,
      version: "3.0.0",
    };

    ({ spawnStub, stdinData } = createSpawnStub({
      stderr: `${ACTIVATION_SEPARATOR}${JSON.stringify(envStub)}${ACTIVATION_SEPARATOR}`,
    }));

    const { env, version, yjit } = await rvm.activate();

    assert.ok(
      spawnStub.calledOnceWithExactly(
        path.join(os.homedir(), ".rvm", "bin", "rvm-auto-ruby"),
        ["-W0", "-rjson"],
        {
          cwd: workspacePath,
          shell: vscode.env.shell,
          env: process.env,
        },
      ),
    );

    assert.ok(stdinData.join("\n").includes(rvm.activationScript));

    assert.strictEqual(version, "3.0.0");
    assert.strictEqual(yjit, true);
    assert.deepStrictEqual(env.ANY, "true");

    installationPathStub.restore();
  });
});
