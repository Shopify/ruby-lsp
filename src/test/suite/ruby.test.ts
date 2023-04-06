import * as assert from "assert";

import * as vscode from "vscode";

import { Ruby, VersionManager } from "../../ruby";

suite("Ruby environment activation", () => {
  let ruby: Ruby;

  test("Activate fetches Ruby information when outside of Ruby LSP", async () => {
    // eslint-disable-next-line no-process-env
    process.env.SHELL = "/bin/bash";

    const context = {
      extensionMode: vscode.ExtensionMode.Test,
    } as vscode.ExtensionContext;

    // eslint-disable-next-line no-process-env
    ruby = new Ruby(context, process.env.PWD);
    await ruby.activateRuby(VersionManager.None);

    assert.ok(ruby.rubyVersion, "Expected Ruby version to be set");
    assert.strictEqual(
      ruby.supportsYjit,
      true,
      "Expected YJIT support to be enabled"
    );
    assert.strictEqual(
      ruby.env.BUNDLE_GEMFILE,
      // eslint-disable-next-line no-process-env
      `${process.env.PWD}/.ruby-lsp/Gemfile`,
      "Expected BUNDLE_GEMFILE to be set"
    );
    assert.strictEqual(ruby.env.BUNDLE_PATH__SYSTEM, "true");
  });
});
