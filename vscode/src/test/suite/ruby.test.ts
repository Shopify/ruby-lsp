import * as assert from "assert";
import * as path from "path";
import * as os from "os";
import * as fs from "fs";

import * as vscode from "vscode";
import sinon from "sinon";
import { afterEach, beforeEach } from "mocha";

import { Ruby, ManagerIdentifier } from "../../ruby";
import { WorkspaceChannel } from "../../workspaceChannel";
import { LOG_CHANNEL } from "../../common";
import * as common from "../../common";
import { Shadowenv, UntrustedWorkspaceError } from "../../ruby/shadowenv";
import { Chruby } from "../../ruby/chruby";
import { ACTIVATION_SEPARATOR, FIELD_SEPARATOR, MissingRubyError, VALUE_SEPARATOR } from "../../ruby/versionManager";

import { createContext, FakeContext, stubWorkspaceConfiguration } from "./helpers";
import { FAKE_TELEMETRY } from "./fakeTelemetry";

suite("Ruby environment activation", () => {
  const workspacePath = path.dirname(path.dirname(path.dirname(path.dirname(__dirname))));
  const workspaceFolder: vscode.WorkspaceFolder = {
    uri: vscode.Uri.file(workspacePath),
    name: path.basename(workspacePath),
    index: 0,
  };
  const outputChannel = new WorkspaceChannel("fake", LOG_CHANNEL);
  let sandbox: sinon.SinonSandbox;
  let context: FakeContext;

  beforeEach(() => {
    sandbox = sinon.createSandbox();
    context = createContext();
  });

  afterEach(() => {
    sandbox.restore();
    context.dispose();
  });

  test("Populates Ruby version and YJIT support from the activation script", async () => {
    stubWorkspaceConfiguration(sandbox, {
      rubyLsp: {
        rubyVersionManager: { identifier: ManagerIdentifier.None },
        bundleGemfile: "",
      },
    });

    const envStub = [
      "3.3.5",
      "~/.gem/ruby/3.3.5,/opt/rubies/3.3.5/lib/ruby/gems/3.3.0",
      "true",
      `ANY${VALUE_SEPARATOR}true`,
    ].join(FIELD_SEPARATOR);

    sandbox.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: `${ACTIVATION_SEPARATOR}${envStub}${ACTIVATION_SEPARATOR}`,
    });

    const ruby = new Ruby(context, workspaceFolder, outputChannel, FAKE_TELEMETRY);
    await ruby.activateRuby();

    assert.strictEqual(ruby.rubyVersion, "3.3.5");
    assert.strictEqual(ruby.yjitEnabled, true);
  });

  test("Deletes verbose and GC settings from activated environment", async () => {
    stubWorkspaceConfiguration(sandbox, {
      rubyLsp: {
        rubyVersionManager: { identifier: ManagerIdentifier.None },
        bundleGemfile: "",
      },
    });

    const envStub = [
      "3.3.5",
      "~/.gem/ruby/3.3.5,/opt/rubies/3.3.5/lib/ruby/gems/3.3.0",
      "true",
      `VERBOSE${VALUE_SEPARATOR}1`,
      `DEBUG${VALUE_SEPARATOR}WARN`,
      `RUBY_GC_HEAP_GROWTH_FACTOR${VALUE_SEPARATOR}1.7`,
    ].join(FIELD_SEPARATOR);

    sandbox.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: `${ACTIVATION_SEPARATOR}${envStub}${ACTIVATION_SEPARATOR}`,
    });

    const ruby = new Ruby(context, workspaceFolder, outputChannel, FAKE_TELEMETRY);
    await ruby.activateRuby();

    assert.strictEqual(ruby.env.VERBOSE, undefined);
    assert.strictEqual(ruby.env.DEBUG, undefined);
    assert.strictEqual(ruby.env.RUBY_GC_HEAP_GROWTH_FACTOR, undefined);
  });

  test("Sets gem path for version managers based on shims", async () => {
    stubWorkspaceConfiguration(sandbox, {
      rubyLsp: {
        rubyVersionManager: { identifier: ManagerIdentifier.Rbenv },
        bundleGemfile: "",
      },
    });

    const envStub = [
      "3.3.5",
      "~/.gem/ruby/3.3.5,/opt/rubies/3.3.5/lib/ruby/gems/3.3.0",
      "true",
      `ANY${VALUE_SEPARATOR}true`,
    ].join(FIELD_SEPARATOR);

    sandbox.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: `${ACTIVATION_SEPARATOR}${envStub}${ACTIVATION_SEPARATOR}`,
    });

    const ruby = new Ruby(context, workspaceFolder, outputChannel, FAKE_TELEMETRY);
    await ruby.activateRuby();

    assert.deepStrictEqual(ruby.gemPath, ["~/.gem/ruby/3.3.5", "/opt/rubies/3.3.5/lib/ruby/gems/3.3.0"]);
  });

  test("mergeComposedEnv merges environment variables", () => {
    const ruby = new Ruby(context, workspaceFolder, outputChannel, FAKE_TELEMETRY);

    assert.deepStrictEqual(ruby.env, {});

    ruby.mergeComposedEnvironment({
      BUNDLE_GEMFILE: ".ruby-lsp/Gemfile",
    });

    assert.deepStrictEqual(ruby.env, { BUNDLE_GEMFILE: ".ruby-lsp/Gemfile" });
  });

  test("Ignores untrusted workspace for telemetry", async () => {
    const telemetry = { ...FAKE_TELEMETRY, logError: sandbox.stub() };
    const ruby = new Ruby(context, workspaceFolder, outputChannel, telemetry);

    sandbox.stub(Shadowenv.prototype, "activate").rejects(new UntrustedWorkspaceError());

    await assert.rejects(async () => {
      await ruby.activateRuby({ identifier: ManagerIdentifier.Shadowenv });
    });

    assert.ok(!telemetry.logError.called);
  });

  test("Ignores missing Ruby version for telemetry", async () => {
    const telemetry = { ...FAKE_TELEMETRY, logError: sandbox.stub() };
    const ruby = new Ruby(context, workspaceFolder, outputChannel, telemetry);

    sandbox
      .stub(Chruby.prototype, "activate")
      .rejects(new MissingRubyError("Cannot find Ruby installation for version 3.4.0"));

    await assert.rejects(async () => {
      await ruby.activateRuby({ identifier: ManagerIdentifier.Chruby });
    });

    assert.ok(!telemetry.logError.called);
  });

  test("Clears outdated workspace Ruby path caches", async () => {
    stubWorkspaceConfiguration(sandbox, {
      rubyLsp: {
        rubyVersionManager: { identifier: ManagerIdentifier.None },
        bundleGemfile: "",
      },
    });

    const envStub = [
      "3.3.5",
      "~/.gem/ruby/3.3.5,/opt/rubies/3.3.5/lib/ruby/gems/3.3.0",
      "true",
      `ANY${VALUE_SEPARATOR}true`,
    ].join(FIELD_SEPARATOR);

    sandbox.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: `${ACTIVATION_SEPARATOR}${envStub}${ACTIVATION_SEPARATOR}`,
    });

    await context.workspaceState.update(
      `rubyLsp.workspaceRubyPath.${workspaceFolder.name}`,
      "/totally/non/existent/path/ruby",
    );
    const ruby = new Ruby(context, workspaceFolder, outputChannel, FAKE_TELEMETRY);

    await ruby.activateRuby();

    assert.strictEqual(context.workspaceState.get(`rubyLsp.workspaceRubyPath.${workspaceFolder.name}`), undefined);
  });

  // eslint-disable-next-line no-template-curly-in-string
  test("Expands ${workspaceFolder} in bundleGemfile setting", async () => {
    const tmpPath = fs.mkdtempSync(path.join(os.tmpdir(), "ruby-lsp-test-"));
    // Use the URI's fsPath to normalize the drive letter casing on Windows (e.g. c: -> C:)
    const normalizedTmpPath = vscode.Uri.file(tmpPath).fsPath;
    const gemfilePath = path.resolve(normalizedTmpPath, "Gemfile");
    fs.writeFileSync(gemfilePath, "");

    const tmpWorkspaceFolder: vscode.WorkspaceFolder = {
      uri: vscode.Uri.file(tmpPath),
      name: path.basename(tmpPath),
      index: 0,
    };

    stubWorkspaceConfiguration(sandbox, {
      rubyLsp: {
        rubyVersionManager: { identifier: ManagerIdentifier.None },
        // eslint-disable-next-line no-template-curly-in-string
        bundleGemfile: "${workspaceFolder}/Gemfile",
      },
    });

    const envStub = [
      "3.3.5",
      "~/.gem/ruby/3.3.5,/opt/rubies/3.3.5/lib/ruby/gems/3.3.0",
      "true",
      `ANY${VALUE_SEPARATOR}true`,
    ].join(FIELD_SEPARATOR);

    sandbox.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: `${ACTIVATION_SEPARATOR}${envStub}${ACTIVATION_SEPARATOR}`,
    });

    const ruby = new Ruby(context, tmpWorkspaceFolder, outputChannel, FAKE_TELEMETRY);
    await ruby.activateRuby();

    assert.strictEqual(ruby.env.BUNDLE_GEMFILE, gemfilePath);
    fs.rmSync(tmpPath, { recursive: true, force: true });
  });

  test("Appends YJIT flag to existing RUBYOPT for Ruby 3.2", async () => {
    stubWorkspaceConfiguration(sandbox, {
      rubyLsp: {
        rubyVersionManager: { identifier: ManagerIdentifier.None },
        bundleGemfile: "",
      },
    });

    const envStub = [
      "3.2.0",
      "~/.gem/ruby/3.2.0,/opt/rubies/3.2.0/lib/ruby/gems/3.2.0",
      "true",
      `RUBYOPT${VALUE_SEPARATOR}-rbundler/setup`,
    ].join(FIELD_SEPARATOR);

    sandbox.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: `${ACTIVATION_SEPARATOR}${envStub}${ACTIVATION_SEPARATOR}`,
    });

    const ruby = new Ruby(context, workspaceFolder, outputChannel, FAKE_TELEMETRY);
    await ruby.activateRuby();

    assert.strictEqual(ruby.env.RUBYOPT, "-rbundler/setup --yjit");
  });

  test("Raises an error if the configured bundleGemfile does not exist", async () => {
    const tmpPath = fs.mkdtempSync(path.join(os.tmpdir(), "ruby-lsp-test-"));
    const tmpWorkspaceFolder: vscode.WorkspaceFolder = {
      uri: vscode.Uri.file(tmpPath),
      name: path.basename(tmpPath),
      index: 0,
    };

    const nonExistentGemfile = path.join(tmpPath, "nonexistent", "Gemfile");

    stubWorkspaceConfiguration(sandbox, {
      rubyLsp: {
        rubyVersionManager: { identifier: ManagerIdentifier.None },
        bundleGemfile: nonExistentGemfile,
      },
    });

    const ruby = new Ruby(context, tmpWorkspaceFolder, outputChannel, FAKE_TELEMETRY);

    await assert.rejects(() => ruby.activateRuby(), {
      message: `The configured bundle gemfile ${nonExistentGemfile} does not exist`,
    });

    fs.rmSync(tmpPath, { recursive: true, force: true });
  });
});
