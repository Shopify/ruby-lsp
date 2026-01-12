import assert from "assert";
import path from "path";
import os from "os";
import fs from "fs";

import * as vscode from "vscode";
import sinon from "sinon";
import { afterEach, beforeEach } from "mocha";

import { Rv } from "../../../ruby/rv";
import { WorkspaceChannel } from "../../../workspaceChannel";
import * as common from "../../../common";
import { ACTIVATION_SEPARATOR, FIELD_SEPARATOR, VALUE_SEPARATOR } from "../../../ruby/versionManager";
import { createContext, FakeContext } from "../helpers";

suite("Rv", () => {
  if (os.platform() === "win32") {
    // eslint-disable-next-line no-console
    console.log("Skipping Rv tests on Windows");
    return;
  }

  let activationPath: vscode.Uri;
  let sandbox: sinon.SinonSandbox;
  let context: FakeContext;

  beforeEach(() => {
    sandbox = sinon.createSandbox();
    context = createContext();
    activationPath = vscode.Uri.joinPath(context.extensionUri, "activation.rb");
  });

  afterEach(() => {
    sandbox.restore();
    context.dispose();
  });

  test("Activates with auto-detected version", async () => {
    const workspacePath = process.env.PWD!;
    const workspaceFolder = {
      uri: vscode.Uri.from({ scheme: "file", path: workspacePath }),
      name: path.basename(workspacePath),
      index: 0,
    };
    const outputChannel = new WorkspaceChannel("fake", common.LOG_CHANNEL);

    const rv = new Rv(workspaceFolder, outputChannel, context, async () => {});

    const envStub = ["3.4.8", "/path/to/gems", "true", `ANY${VALUE_SEPARATOR}true`].join(FIELD_SEPARATOR);

    const execStub = sandbox.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: `${ACTIVATION_SEPARATOR}${envStub}${ACTIVATION_SEPARATOR}`,
    });

    // Stub findRv to return the executable path
    sandbox.stub(rv, "findRv" as any).resolves("rv");

    const { env, version, yjit } = await rv.activate();

    assert.ok(
      execStub.calledOnceWithExactly(`rv ruby run -- -EUTF-8:UTF-8 '${activationPath.fsPath}'`, {
        cwd: workspacePath,
        shell: vscode.env.shell,

        env: process.env,
        encoding: "utf-8",
      }),
    );

    assert.strictEqual(version, "3.4.8");
    assert.strictEqual(yjit, true);
    assert.strictEqual(env.ANY, "true");
  });

  test("Allows configuring where rv is installed", async () => {
    const workspacePath = fs.mkdtempSync(path.join(os.tmpdir(), "ruby-lsp-test-"));
    const workspaceFolder = {
      uri: vscode.Uri.from({ scheme: "file", path: workspacePath }),
      name: path.basename(workspacePath),
      index: 0,
    };
    const outputChannel = new WorkspaceChannel("fake", common.LOG_CHANNEL);

    const rv = new Rv(workspaceFolder, outputChannel, context, async () => {});

    const envStub = ["3.4.8", "/path/to/gems", "true", `ANY${VALUE_SEPARATOR}true`].join(FIELD_SEPARATOR);

    const execStub = sandbox.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: `${ACTIVATION_SEPARATOR}${envStub}${ACTIVATION_SEPARATOR}`,
    });

    const rvPath = path.join(workspacePath, "rv");
    fs.writeFileSync(rvPath, "fakeRvBinary");

    // Stub findRv to return the configured executable path
    sandbox.stub(rv, "findRv" as any).resolves(rvPath);

    const configStub = sinon.stub(vscode.workspace, "getConfiguration").returns({
      get: (name: string) => {
        if (name === "rubyVersionManager.rvExecutablePath") {
          return rvPath;
        }
        return "";
      },
    } as any);

    const { env, version, yjit } = await rv.activate();

    assert.ok(
      execStub.calledOnceWithExactly(`${rvPath} ruby run -- -EUTF-8:UTF-8 '${activationPath.fsPath}'`, {
        cwd: workspacePath,
        shell: vscode.env.shell,

        env: process.env,
        encoding: "utf-8",
      }),
    );

    assert.strictEqual(version, "3.4.8");
    assert.strictEqual(yjit, true);
    assert.deepStrictEqual(env.ANY, "true");

    execStub.restore();
    configStub.restore();
    fs.rmSync(workspacePath, { recursive: true, force: true });
  });
});
