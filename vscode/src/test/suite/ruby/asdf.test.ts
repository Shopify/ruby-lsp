import assert from "assert";
import path from "path";
import os from "os";

import * as vscode from "vscode";
import sinon from "sinon";

import { Asdf } from "../../../ruby/asdf";
import { WorkspaceChannel } from "../../../workspaceChannel";
import * as common from "../../../common";

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
    const asdf = new Asdf(workspaceFolder, outputChannel);
    const activationScript =
      "STDERR.print({env: ENV.to_h,yjit:!!defined?(RubyVM::YJIT),version:RUBY_VERSION}.to_json)";

    const execStub = sinon.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: JSON.stringify({
        env: { ANY: "true" },
        yjit: true,
        version: "3.0.0",
      }),
    });

    const findInstallationStub = sinon
      .stub(asdf, "findAsdfInstallation")
      .resolves(vscode.Uri.file(`${os.homedir()}/.asdf/asdf.sh`));
    const findDataDirStub = sinon
      .stub(asdf, "findAsdfDataDir")
      .resolves(vscode.Uri.file(`${os.homedir()}/.asdf`));
    const shellStub = sinon.stub(vscode.env, "shell").get(() => "/bin/bash");

    const { env, version, yjit } = await asdf.activate();

    assert.ok(
      execStub.calledOnceWithExactly(
        `. ${os.homedir()}/.asdf/asdf.sh && asdf exec ruby -W0 -rjson -e '${activationScript}'`,
        {
          cwd: workspacePath,
          shell: "/bin/bash",
          env: {
            // eslint-disable-next-line no-process-env
            ...process.env,
            ASDF_DIR: `${os.homedir()}/.asdf`,
            ASDF_DATA_DIR: `${os.homedir()}/.asdf`,
          },
        },
      ),
    );

    assert.strictEqual(version, "3.0.0");
    assert.strictEqual(yjit, true);
    assert.ok(env.PATH!.includes(`${os.homedir()}/.asdf/shims`));
    assert.strictEqual(env.ANY, "true");

    execStub.restore();
    findInstallationStub.restore();
    findDataDirStub.restore();
    shellStub.restore();
  });
});
