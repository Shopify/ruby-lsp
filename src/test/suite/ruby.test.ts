import * as assert from "assert";
import * as fs from "fs";
import * as path from "path";
import * as os from "os";

import * as vscode from "vscode";

import { Ruby, VersionManager } from "../../ruby";

suite("Ruby environment activation", () => {
  let ruby: Ruby;

  test("Activate fetches Ruby information when outside of Ruby LSP", async () => {
    // eslint-disable-next-line no-process-env
    process.env.SHELL = "/bin/bash";

    const tmpPath = fs.mkdtempSync(path.join(os.tmpdir(), "ruby-lsp-test-"));
    fs.writeFileSync(path.join(tmpPath, ".ruby-version"), "3.2.2");

    const context = {
      extensionMode: vscode.ExtensionMode.Test,
    } as vscode.ExtensionContext;

    ruby = new Ruby(context, tmpPath);
    await ruby.activateRuby(
      // eslint-disable-next-line no-process-env
      process.env.CI ? VersionManager.None : VersionManager.Chruby,
    );

    assert.ok(ruby.rubyVersion, "Expected Ruby version to be set");
    assert.strictEqual(
      ruby.supportsYjit,
      true,
      "Expected YJIT support to be enabled",
    );

    fs.rmSync(tmpPath, { recursive: true, force: true });
  });
});
