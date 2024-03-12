import * as assert from "assert";
import * as fs from "fs";
import * as path from "path";
import * as os from "os";

import * as vscode from "vscode";

import { Ruby, ManagerIdentifier } from "../../ruby";
import { WorkspaceChannel } from "../../workspaceChannel";
import { LOG_CHANNEL } from "../../common";

suite("Ruby environment activation", () => {
  let ruby: Ruby;

  test("Activate fetches Ruby information when outside of Ruby LSP", async () => {
    if (os.platform() !== "win32") {
      // eslint-disable-next-line no-process-env
      process.env.SHELL = "/bin/bash";
    }

    const tmpPath = fs.mkdtempSync(path.join(os.tmpdir(), "ruby-lsp-test-"));
    fs.writeFileSync(path.join(tmpPath, ".ruby-version"), "3.3.0");

    const context = {
      extensionMode: vscode.ExtensionMode.Test,
    } as vscode.ExtensionContext;
    const outputChannel = new WorkspaceChannel("fake", LOG_CHANNEL);

    ruby = new Ruby(
      context,
      {
        uri: vscode.Uri.file(tmpPath),
      } as vscode.WorkspaceFolder,
      outputChannel,
    );
    await ruby.activateRuby(
      // eslint-disable-next-line no-process-env
      process.env.CI ? ManagerIdentifier.None : ManagerIdentifier.Chruby,
    );

    assert.ok(ruby.rubyVersion, "Expected Ruby version to be set");
    assert.notStrictEqual(
      ruby.yjitEnabled,
      undefined,
      "Expected YJIT support to be set to true or false",
    );

    fs.rmSync(tmpPath, { recursive: true, force: true });
  });
});
