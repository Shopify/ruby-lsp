import assert from "assert";
import path from "path";
import os from "os";

import * as vscode from "vscode";
import sinon from "sinon";

import { Asdf } from "../../../ruby/asdf";
import { WorkspaceChannel } from "../../../workspaceChannel";
import * as common from "../../../common";
import { ACTIVATION_SEPARATOR } from "../../../ruby/versionManager";

suite("Asdf", () => {
  if (os.platform() === "win32") {
    // eslint-disable-next-line no-console
    console.log("Skipping Asdf tests on Windows");
    return;
  }

  test("Finds Ruby based on .tool-versions", async () => {
    // eslint-disable-next-line no-process-env
    const workspacePath = process.env.PWD!;
    const workspaceFolder = {
      uri: vscode.Uri.from({ scheme: "file", path: workspacePath }),
      name: path.basename(workspacePath),
      index: 0,
    };
    const outputChannel = new WorkspaceChannel("fake", common.LOG_CHANNEL);
    const asdf = new Asdf(workspaceFolder, outputChannel, async () => {});
    const envStub = {
      env: { ANY: "true" },
      yjit: true,
      version: "3.0.0",
    };

    const execStub = sinon.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: `${ACTIVATION_SEPARATOR}${JSON.stringify(envStub)}${ACTIVATION_SEPARATOR}`,
    });

    const findInstallationStub = sinon
      .stub(asdf, "findAsdfInstallation")
      .resolves(vscode.Uri.file(`${os.homedir()}/.asdf/asdf.sh`));
    const shellStub = sinon.stub(vscode.env, "shell").get(() => "/bin/bash");

    const { env, version, yjit } = await asdf.activate();

    assert.ok(
      execStub.calledOnceWithExactly(
        `. ${os.homedir()}/.asdf/asdf.sh && asdf exec ruby -W0 -rjson -e '${asdf.activationScript}'`,
        {
          cwd: workspacePath,
          shell: "/bin/bash",
          // eslint-disable-next-line no-process-env
          env: process.env,
          encoding: "utf-8",
        },
      ),
    );

    assert.strictEqual(version, "3.0.0");
    assert.strictEqual(yjit, true);
    assert.strictEqual(env.ANY, "true");

    execStub.restore();
    findInstallationStub.restore();
    shellStub.restore();
  });

  test("Searches for asdf.fish when using the fish shell", async () => {
    // eslint-disable-next-line no-process-env
    const workspacePath = process.env.PWD!;
    const workspaceFolder = {
      uri: vscode.Uri.from({ scheme: "file", path: workspacePath }),
      name: path.basename(workspacePath),
      index: 0,
    };
    const outputChannel = new WorkspaceChannel("fake", common.LOG_CHANNEL);
    const asdf = new Asdf(workspaceFolder, outputChannel, async () => {});
    const envStub = {
      env: { ANY: "true" },
      yjit: true,
      version: "3.0.0",
    };

    const execStub = sinon.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: `${ACTIVATION_SEPARATOR}${JSON.stringify(envStub)}${ACTIVATION_SEPARATOR}`,
    });

    const findInstallationStub = sinon
      .stub(asdf, "findAsdfInstallation")
      .resolves(vscode.Uri.file(`${os.homedir()}/.asdf/asdf.fish`));
    const shellStub = sinon
      .stub(vscode.env, "shell")
      .get(() => "/opt/homebrew/bin/fish");

    const { env, version, yjit } = await asdf.activate();

    assert.ok(
      execStub.calledOnceWithExactly(
        `. ${os.homedir()}/.asdf/asdf.fish && asdf exec ruby -W0 -rjson -e '${asdf.activationScript}'`,
        {
          cwd: workspacePath,
          shell: "/opt/homebrew/bin/fish",
          // eslint-disable-next-line no-process-env
          env: process.env,
          encoding: "utf-8",
        },
      ),
    );

    assert.strictEqual(version, "3.0.0");
    assert.strictEqual(yjit, true);
    assert.strictEqual(env.ANY, "true");

    execStub.restore();
    findInstallationStub.restore();
    shellStub.restore();
  });
});
