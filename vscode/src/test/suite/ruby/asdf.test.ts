import assert from "assert";
import path from "path";
import os from "os";

import * as vscode from "vscode";
import sinon from "sinon";

import { Asdf } from "../../../ruby/asdf";
import { WorkspaceChannel } from "../../../workspaceChannel";
import * as common from "../../../common";
import {
  ACTIVATION_SEPARATOR,
  FIELD_SEPARATOR,
  VALUE_SEPARATOR,
} from "../../../ruby/versionManager";
import { fakeContext } from "../helpers";

suite("Asdf", () => {
  if (os.platform() === "win32") {
    // eslint-disable-next-line no-console
    console.log("Skipping Asdf tests on Windows");
    return;
  }
  const context = fakeContext();

  test("Finds Ruby based on .tool-versions", async () => {
    // eslint-disable-next-line no-process-env
    const workspacePath = process.env.PWD!;
    const workspaceFolder = {
      uri: vscode.Uri.from({ scheme: "file", path: workspacePath }),
      name: path.basename(workspacePath),
      index: 0,
    };
    const outputChannel = new WorkspaceChannel("fake", common.LOG_CHANNEL);
    const asdf = new Asdf(
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

    const findInstallationStub = sinon
      .stub(asdf, "findAsdfInstallation")
      .resolves(vscode.Uri.file(`${os.homedir()}/.asdf/asdf.sh`));
    const shellStub = sinon.stub(vscode.env, "shell").get(() => "/bin/bash");

    const { env, version, yjit } = await asdf.activate();
    const baseCommand = `. ${os.homedir()}/.asdf/asdf.sh && asdf exec ruby`;

    assert.ok(
      execStub.calledOnceWithExactly(
        `${baseCommand} -EUTF-8:UTF-8 '${context.extensionUri.fsPath}/activation.rb'`,
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
    const asdf = new Asdf(
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

    const findInstallationStub = sinon
      .stub(asdf, "findAsdfInstallation")
      .resolves(vscode.Uri.file(`${os.homedir()}/.asdf/asdf.fish`));
    const shellStub = sinon
      .stub(vscode.env, "shell")
      .get(() => "/opt/homebrew/bin/fish");

    const { env, version, yjit } = await asdf.activate();
    const baseCommand = `. ${os.homedir()}/.asdf/asdf.fish && asdf exec ruby`;

    assert.ok(
      execStub.calledOnceWithExactly(
        `${baseCommand} -EUTF-8:UTF-8 '${context.extensionUri.fsPath}/activation.rb'`,
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
