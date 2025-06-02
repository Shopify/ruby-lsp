/* eslint-disable no-process-env */
import * as assert from "assert";
import * as path from "path";

import * as vscode from "vscode";
import sinon from "sinon";
import { afterEach, beforeEach } from "mocha";

import { Ruby, ManagerIdentifier } from "../../ruby";
import { WorkspaceChannel } from "../../workspaceChannel";
import { LOG_CHANNEL } from "../../common";
import * as common from "../../common";
import { Shadowenv, UntrustedWorkspaceError } from "../../ruby/shadowenv";
import {
  ACTIVATION_SEPARATOR,
  FIELD_SEPARATOR,
  VALUE_SEPARATOR,
} from "../../ruby/versionManager";

import { CONTEXT } from "./helpers";
import { FAKE_TELEMETRY } from "./fakeTelemetry";

suite("Ruby environment activation", () => {
  const workspacePath = path.dirname(
    path.dirname(path.dirname(path.dirname(__dirname))),
  );
  const workspaceFolder: vscode.WorkspaceFolder = {
    uri: vscode.Uri.file(workspacePath),
    name: path.basename(workspacePath),
    index: 0,
  };
  const outputChannel = new WorkspaceChannel("fake", LOG_CHANNEL);
  let sandbox: sinon.SinonSandbox;

  beforeEach(() => {
    sandbox = sinon.createSandbox();
  });

  afterEach(() => {
    sandbox.restore();
  });

  test("Activate fetches Ruby information when outside of Ruby LSP", async () => {
    const manager = process.env.CI
      ? ManagerIdentifier.None
      : ManagerIdentifier.Chruby;

    sandbox.stub(vscode.workspace, "getConfiguration").returns({
      get: (name: string) => {
        if (name === "rubyVersionManager") {
          return { identifier: manager };
        } else if (name === "bundleGemfile") {
          return "";
        }

        return undefined;
      },
    } as unknown as vscode.WorkspaceConfiguration);

    const ruby = new Ruby(
      CONTEXT,
      workspaceFolder,
      outputChannel,
      FAKE_TELEMETRY,
    );
    await ruby.activateRuby();

    assert.ok(ruby.rubyVersion, "Expected Ruby version to be set");
    assert.notStrictEqual(
      ruby.yjitEnabled,
      undefined,
      "Expected YJIT support to be set to true or false",
    );
  }).timeout(10000);

  test("Deletes verbose and GC settings from activated environment", async () => {
    const manager = process.env.CI
      ? ManagerIdentifier.None
      : ManagerIdentifier.Chruby;

    sandbox.stub(vscode.workspace, "getConfiguration").returns({
      get: (name: string) => {
        if (name === "rubyVersionManager") {
          return { identifier: manager };
        } else if (name === "bundleGemfile") {
          return "";
        }

        return undefined;
      },
    } as unknown as vscode.WorkspaceConfiguration);

    const ruby = new Ruby(
      CONTEXT,
      workspaceFolder,
      outputChannel,
      FAKE_TELEMETRY,
    );

    process.env.VERBOSE = "1";
    process.env.DEBUG = "WARN";
    process.env.RUBY_GC_HEAP_GROWTH_FACTOR = "1.7";
    await ruby.activateRuby();

    assert.strictEqual(ruby.env.VERBOSE, undefined);
    assert.strictEqual(ruby.env.DEBUG, undefined);
    assert.strictEqual(ruby.env.RUBY_GC_HEAP_GROWTH_FACTOR, undefined);
    delete process.env.VERBOSE;
    delete process.env.DEBUG;
    delete process.env.RUBY_GC_HEAP_GROWTH_FACTOR;
  });

  test("Sets gem path for version managers based on shims", async () => {
    sandbox.stub(vscode.workspace, "getConfiguration").returns({
      get: (name: string) => {
        if (name === "rubyVersionManager") {
          return { identifier: ManagerIdentifier.Rbenv };
        } else if (name === "bundleGemfile") {
          return "";
        }

        return undefined;
      },
    } as unknown as vscode.WorkspaceConfiguration);

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

    const ruby = new Ruby(
      CONTEXT,
      workspaceFolder,
      outputChannel,
      FAKE_TELEMETRY,
    );
    await ruby.activateRuby();

    assert.deepStrictEqual(ruby.gemPath, [
      "~/.gem/ruby/3.3.5",
      "/opt/rubies/3.3.5/lib/ruby/gems/3.3.0",
    ]);
  });

  test("mergeComposedEnv merges environment variables", () => {
    const ruby = new Ruby(
      CONTEXT,
      workspaceFolder,
      outputChannel,
      FAKE_TELEMETRY,
    );

    assert.deepStrictEqual(ruby.env, {});

    ruby.mergeComposedEnvironment({
      BUNDLE_GEMFILE: ".ruby-lsp/Gemfile",
    });

    assert.deepStrictEqual(ruby.env, { BUNDLE_GEMFILE: ".ruby-lsp/Gemfile" });
  });

  test("Ignores untrusted workspace for telemetry", async () => {
    const telemetry = { ...FAKE_TELEMETRY, logError: sinon.stub() };
    const ruby = new Ruby(CONTEXT, workspaceFolder, outputChannel, telemetry);

    sandbox
      .stub(Shadowenv.prototype, "activate")
      .rejects(new UntrustedWorkspaceError());

    await assert.rejects(async () => {
      await ruby.activateRuby({ identifier: ManagerIdentifier.Shadowenv });
    });

    assert.ok(!telemetry.logError.called);
  });

  test("Clears outdated workspace Ruby path caches", async () => {
    const manager = process.env.CI
      ? ManagerIdentifier.None
      : ManagerIdentifier.Chruby;

    sandbox.stub(vscode.workspace, "getConfiguration").returns({
      get: (name: string) => {
        if (name === "rubyVersionManager") {
          return { identifier: manager };
        } else if (name === "bundleGemfile") {
          return "";
        }

        return undefined;
      },
    } as unknown as vscode.WorkspaceConfiguration);

    await CONTEXT.workspaceState.update(
      `rubyLsp.workspaceRubyPath.${workspaceFolder.name}`,
      "/totally/non/existent/path/ruby",
    );
    const ruby = new Ruby(
      CONTEXT,
      workspaceFolder,
      outputChannel,
      FAKE_TELEMETRY,
    );

    await ruby.activateRuby();

    assert.strictEqual(
      CONTEXT.workspaceState.get(
        `rubyLsp.workspaceRubyPath.${workspaceFolder.name}`,
      ),
      undefined,
    );
  });
});
