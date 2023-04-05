import * as assert from "assert";

import { Ruby, VersionManager } from "../../ruby";

suite("Ruby environment activation", () => {
  let ruby: Ruby;

  test("Activate fetches Ruby information when outside of Ruby LSP", async () => {
    ruby = new Ruby("fake/some/project");
    await ruby.activateRuby(VersionManager.None);

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
    assert.strictEqual(ruby.env.BUNDLE_PATH__SYSTEM, "true");
  });

  test("Activate fetches Ruby information when working on the Ruby LSP", async () => {
    ruby = new Ruby("/fake/ruby-lsp");
    await ruby.activateRuby(VersionManager.None);

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
    assert.strictEqual(ruby.env.BUNDLE_PATH__SYSTEM, undefined);
  });
});
