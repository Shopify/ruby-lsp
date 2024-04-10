import assert from "assert";
import path from "path";
import fs from "fs";
import os from "os";

import * as vscode from "vscode";
import sinon from "sinon";

import { None } from "../../../ruby/none";
import { WorkspaceChannel } from "../../../workspaceChannel";
import * as common from "../../../common";

suite("None", () => {
  test("Invokes Ruby directly", async () => {
    const workspacePath = fs.mkdtempSync(
      path.join(os.tmpdir(), "ruby-lsp-test-"),
    );
    const uri = vscode.Uri.file(workspacePath);
    const workspaceFolder = {
      uri,
      name: path.basename(workspacePath),
      index: 0,
    };
    const outputChannel = new WorkspaceChannel("fake", common.LOG_CHANNEL);
    const none = new None(workspaceFolder, outputChannel);

    const activationScript =
      "STDERR.print({ env: ENV.to_h, yjit: !!defined?(RubyVM::YJIT), version: RUBY_VERSION }.to_json)";

    const execStub = sinon.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: JSON.stringify({
        env: { ANY: "true" },
        yjit: true,
        version: "3.0.0",
      }),
    });
    const { env, version, yjit } = await none.activate();

    assert.ok(
      execStub.calledOnceWithExactly(
        `ruby -W0 -rjson -e '${activationScript}'`,
        { cwd: uri.fsPath },
      ),
    );

    assert.strictEqual(version, "3.0.0");
    assert.strictEqual(yjit, true);
    assert.deepStrictEqual(env.ANY, "true");

    execStub.restore();
    fs.rmSync(workspacePath, { recursive: true, force: true });
  });
});
