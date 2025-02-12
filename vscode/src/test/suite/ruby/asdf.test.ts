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

suite("Asdf", () => {
  if (os.platform() === "win32") {
    // eslint-disable-next-line no-console
    console.log("Skipping Asdf tests on Windows");
    return;
  }
  const context = {
    extensionMode: vscode.ExtensionMode.Test,
    subscriptions: [],
    workspaceState: {
      get: (_name: string) => undefined,
      update: (_name: string, _value: any) => Promise.resolve(),
    },
    extensionUri: vscode.Uri.parse("file:///fake"),
  } as unknown as vscode.ExtensionContext;
  // eslint-disable-next-line no-process-env
  const workspacePath = process.env.PWD!;
  const workspaceFolder = {
    uri: vscode.Uri.from({ scheme: "file", path: workspacePath }),
    name: path.basename(workspacePath),
    index: 0,
  };
  const outputChannel = new WorkspaceChannel("fake", common.LOG_CHANNEL);

  test("Finds Ruby based on .tool-versions", async () => {
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
      .resolves(`${os.homedir()}/.asdf/asdf.sh`);
    const shellStub = sinon.stub(vscode.env, "shell").get(() => "/bin/bash");

    const { env, version, yjit } = await asdf.activate();

    assert.ok(
      execStub.calledOnceWithExactly(
        `. ${os.homedir()}/.asdf/asdf.sh && asdf exec ruby -EUTF-8:UTF-8 '/fake/activation.rb'`,
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
      .resolves(`${os.homedir()}/.asdf/asdf.fish`);
    const shellStub = sinon
      .stub(vscode.env, "shell")
      .get(() => "/opt/homebrew/bin/fish");

    const { env, version, yjit } = await asdf.activate();

    assert.ok(
      execStub.calledOnceWithExactly(
        `. ${os.homedir()}/.asdf/asdf.fish && asdf exec ruby -EUTF-8:UTF-8 '/fake/activation.rb'`,
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

  test("Finds ASDF executable for Homebrew if script is not available", async () => {
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
      .resolves(undefined);

    const fsStub = sinon.stub(vscode.workspace, "fs").value({
      stat: () => Promise.resolve(undefined),
    });

    const { env, version, yjit } = await asdf.activate();

    assert.ok(
      execStub.calledOnceWithExactly(
        `/opt/homebrew/bin/asdf exec ruby -EUTF-8:UTF-8 '/fake/activation.rb'`,
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
    assert.strictEqual(env.ANY, "true");

    fsStub.restore();
    execStub.restore();
    findInstallationStub.restore();
  });

  test("Uses ASDF executable in PATH if script and Homebrew executable are not available", async () => {
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
      .resolves(undefined);

    const { env, version, yjit } = await asdf.activate();

    assert.ok(
      execStub.calledOnceWithExactly(
        `asdf exec ruby -EUTF-8:UTF-8 '/fake/activation.rb'`,
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
    assert.strictEqual(env.ANY, "true");

    execStub.restore();
    findInstallationStub.restore();
  });
});
