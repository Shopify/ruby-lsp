import assert from "assert";
import path from "path";
import fs from "fs";
import os from "os";

import * as vscode from "vscode";
import sinon from "sinon";
import { afterEach, beforeEach } from "mocha";

import { None } from "../../../ruby/none";
import { WorkspaceChannel } from "../../../workspaceChannel";
import * as common from "../../../common";
import { ACTIVATION_SEPARATOR, FIELD_SEPARATOR, VALUE_SEPARATOR } from "../../../ruby/versionManager";
import { createContext, FakeContext } from "../helpers";

suite("None", () => {
  let context: FakeContext;
  let sandbox: sinon.SinonSandbox;

  beforeEach(() => {
    sandbox = sinon.createSandbox();
    context = createContext();
  });

  afterEach(() => {
    sandbox.restore();
    context.dispose();
  });

  test("Invokes Ruby directly", async () => {
    const workspacePath = fs.mkdtempSync(path.join(os.tmpdir(), "ruby-lsp-test-"));
    const uri = vscode.Uri.file(workspacePath);
    const workspaceFolder = {
      uri,
      name: path.basename(workspacePath),
      index: 0,
    };
    const outputChannel = new WorkspaceChannel("fake", common.LOG_CHANNEL);
    const none = new None(workspaceFolder, outputChannel, context, async () => {});

    const envStub = ["3.0.0", "/path/to/gems", "true", `ANY${VALUE_SEPARATOR}true`].join(FIELD_SEPARATOR);

    const execStub = sandbox.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: `${ACTIVATION_SEPARATOR}${envStub}${ACTIVATION_SEPARATOR}`,
    });

    const { env, version, yjit } = await none.activate();
    const activationUri = vscode.Uri.joinPath(context.extensionUri, "activation.rb");

    // We must not set the shell on Windows
    const shell = os.platform() === "win32" ? undefined : vscode.env.shell;

    assert.ok(
      execStub.calledOnceWithExactly(`ruby -EUTF-8:UTF-8 '${activationUri.fsPath}'`, {
        cwd: uri.fsPath,
        shell,
        env: process.env,
        encoding: "utf-8",
      }),
    );

    assert.strictEqual(version, "3.0.0");
    assert.strictEqual(yjit, true);
    assert.deepStrictEqual(env.ANY, "true");

    fs.rmSync(workspacePath, { recursive: true, force: true });
  });
});
