import assert from "assert";
import path from "path";
import fs from "fs";
import os from "os";

import * as vscode from "vscode";
import sinon from "sinon";
import { afterEach, beforeEach } from "mocha";

import { Custom } from "../../../ruby/custom";
import { WorkspaceChannel } from "../../../workspaceChannel";
import * as common from "../../../common";
import { ACTIVATION_SEPARATOR, FIELD_SEPARATOR, VALUE_SEPARATOR } from "../../../ruby/versionManager";
import { createContext, FakeContext } from "../helpers";

suite("Custom", () => {
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

  test("Invokes custom script and then Ruby", async () => {
    const workspacePath = fs.mkdtempSync(path.join(os.tmpdir(), "ruby-lsp-test-"));
    const uri = vscode.Uri.file(workspacePath);
    const workspaceFolder = {
      uri,
      name: path.basename(workspacePath),
      index: 0,
    };
    const outputChannel = new WorkspaceChannel("fake", common.LOG_CHANNEL);
    const custom = new Custom(workspaceFolder, outputChannel, context, async () => {});

    const envStub = ["3.0.0", "/path/to/gems", "true", `ANY${VALUE_SEPARATOR}true`].join(FIELD_SEPARATOR);

    const execStub = sandbox.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: `${ACTIVATION_SEPARATOR}${envStub}${ACTIVATION_SEPARATOR}`,
    });

    sandbox.stub(custom, "customCommand").returns("my_version_manager activate_env");
    const { env, version, yjit } = await custom.activate();
    const activationUri = vscode.Uri.joinPath(context.extensionUri, "activation.rb");

    // We must not set the shell on Windows
    const shell = common.isWindows() ? undefined : vscode.env.shell;

    assert.ok(
      execStub.calledOnceWithExactly(
        `my_version_manager activate_env && ruby -EUTF-8:UTF-8 '${activationUri.fsPath}'`,
        {
          cwd: uri.fsPath,
          shell,
          env: process.env,
          encoding: "utf-8",
        },
      ),
    );

    assert.strictEqual(version, "3.0.0");
    assert.strictEqual(yjit, true);
    assert.deepStrictEqual(env.ANY, "true");

    fs.rmSync(workspacePath, { recursive: true, force: true });
  });
});
