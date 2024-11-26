import assert from "assert";
import path from "path";
import fs from "fs";
import os from "os";

import * as vscode from "vscode";

import { None } from "../../../ruby/none";
import { WorkspaceChannel } from "../../../workspaceChannel";
import * as common from "../../../common";
import { ACTIVATION_SEPARATOR } from "../../../ruby/versionManager";
import { createSpawnStub } from "../testHelpers";

suite("None", () => {
  let spawnStub: sinon.SinonStub;
  let stdinData: string[];

  teardown(() => {
    spawnStub?.restore();
  });

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
    const none = new None(workspaceFolder, outputChannel, async () => {});

    const envStub = {
      env: { ANY: "true" },
      yjit: true,
      version: "3.0.0",
    };

    ({ spawnStub, stdinData } = createSpawnStub({
      stderr: `${ACTIVATION_SEPARATOR}${JSON.stringify(envStub)}${ACTIVATION_SEPARATOR}`,
    }));

    const { env, version, yjit } = await none.activate();

    // We must not set the shell on Windows
    const shell = os.platform() === "win32" ? undefined : vscode.env.shell;

    assert.ok(
      spawnStub.calledOnceWithExactly("ruby", ["-W0", "-rjson"], {
        cwd: uri.fsPath,
        shell,
        // eslint-disable-next-line no-process-env
        env: process.env,
      }),
    );

    assert.ok(stdinData.join("\n").includes(none.activationScript));

    assert.strictEqual(version, "3.0.0");
    assert.strictEqual(yjit, true);
    assert.deepStrictEqual(env.ANY, "true");

    fs.rmSync(workspacePath, { recursive: true, force: true });
  });
});
