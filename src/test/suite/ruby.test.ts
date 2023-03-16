import * as assert from "assert";

import { before, after } from "mocha";
import * as vscode from "vscode";

import { Ruby } from "../../ruby";

suite("Ruby environment activation", () => {
  let ruby: Ruby;
  const configuration = vscode.workspace.getConfiguration("rubyLsp");
  const currentManager = configuration.get("rubyVersionManager")!;

  before(async () => {
    await configuration.update("rubyVersionManager", "none", true, true);
  });

  after(async () => {
    await configuration.update(
      "rubyVersionManager",
      currentManager,
      true,
      true
    );
  });

  test("Activate fetches Ruby information when outside of Ruby LSP", async () => {
    ruby = new Ruby("fake/some/project");
    await ruby.activateRuby();

    assert.ok(ruby.rubyVersion, "Expected Ruby version to be set");
    assert.strictEqual(
      ruby.supportsYjit,
      false,
      "Expected YJIT support to be enabled"
    );
    assert.strictEqual(
      ruby.env.BUNDLE_GEMFILE,
      "fake/some/project/.ruby-lsp/Gemfile",
      "Expected BUNDLE_GEMFILE to be set"
    );
  });

  test("Activate fetches Ruby information when working on the Ruby LSP", async () => {
    ruby = new Ruby("/fake/ruby-lsp");
    await ruby.activateRuby();

    assert.ok(ruby.rubyVersion, "Expected Ruby version to be set");
    assert.strictEqual(
      ruby.supportsYjit,
      false,
      "Expected YJIT support to be enabled"
    );
    assert.strictEqual(
      ruby.env.BUNDLE_GEMFILE,
      undefined,
      "Expected BUNDLE_GEMFILE to not be set for the ruby-lsp folder"
    );
  });
});
