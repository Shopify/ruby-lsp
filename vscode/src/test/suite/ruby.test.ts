/* eslint-disable no-process-env */
import * as assert from "assert";
import * as path from "path";
import os from "os";

import * as vscode from "vscode";
import sinon from "sinon";

import { Ruby, ManagerIdentifier } from "../../ruby";
import { WorkspaceChannel } from "../../workspaceChannel";
import { LOG_CHANNEL } from "../../common";
import * as common from "../../common";
import { ACTIVATION_SEPARATOR } from "../../ruby/versionManager";

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
  const context = {
    extensionMode: vscode.ExtensionMode.Test,
    workspaceState: {
      get: () => undefined,
      update: () => undefined,
    },
  } as unknown as vscode.ExtensionContext;
  const outputChannel = new WorkspaceChannel("fake", LOG_CHANNEL);

  test("Activate fetches Ruby information when outside of Ruby LSP", async () => {
    const manager = process.env.CI
      ? ManagerIdentifier.None
      : ManagerIdentifier.Chruby;

    const configStub = sinon
      .stub(vscode.workspace, "getConfiguration")
      .returns({
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
      context,
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

    configStub.restore();
  }).timeout(10000);

  test("Deletes verbose and GC settings from activated environment", async () => {
    const manager = process.env.CI
      ? ManagerIdentifier.None
      : ManagerIdentifier.Chruby;

    const configStub = sinon
      .stub(vscode.workspace, "getConfiguration")
      .returns({
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
      context,
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
    configStub.restore();
  });

  test("Sets gem path for version managers based on shims", async () => {
    const configStub = sinon
      .stub(vscode.workspace, "getConfiguration")
      .returns({
        get: (name: string) => {
          if (name === "rubyVersionManager") {
            return { identifier: ManagerIdentifier.Rbenv };
          } else if (name === "bundleGemfile") {
            return "";
          }

          return undefined;
        },
      } as unknown as vscode.WorkspaceConfiguration);

    const envStub = {
      env: { ANY: "true" },
      yjit: true,
      version: "3.3.5",
      gemPath: ["~/.gem/ruby/3.3.5", "/opt/rubies/3.3.5/lib/ruby/gems/3.3.0"],
    };

    const execStub = sinon.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: `${ACTIVATION_SEPARATOR}${JSON.stringify(envStub)}${ACTIVATION_SEPARATOR}`,
    });

    const ruby = new Ruby(
      context,
      workspaceFolder,
      outputChannel,
      FAKE_TELEMETRY,
    );
    await ruby.activateRuby();
    execStub.restore();
    configStub.restore();

    assert.deepStrictEqual(ruby.gemPath, [
      "~/.gem/ruby/3.3.5",
      "/opt/rubies/3.3.5/lib/ruby/gems/3.3.0",
    ]);
  });

  test("mergeComposedEnv merges environment variables", () => {
    const ruby = new Ruby(
      context,
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

  test("Adds local exe directory to PATH when working on the Ruby LSP itself", async () => {
    if (os.platform() === "win32") {
      // We don't mutate the path on Windows
      return;
    }

    const manager = process.env.CI
      ? ManagerIdentifier.None
      : ManagerIdentifier.Chruby;

    const configStub = sinon
      .stub(vscode.workspace, "getConfiguration")
      .returns({
        get: (name: string) => {
          if (name === "rubyVersionManager") {
            return { identifier: manager };
          } else if (name === "bundleGemfile") {
            return "";
          }

          return undefined;
        },
      } as unknown as vscode.WorkspaceConfiguration);

    const workspacePath = path.dirname(
      path.dirname(path.dirname(path.dirname(__dirname))),
    );
    const lspFolder: vscode.WorkspaceFolder = {
      uri: vscode.Uri.file(workspacePath),
      name: path.basename(workspacePath),
      index: 0,
    };
    const ruby = new Ruby(context, lspFolder, outputChannel, FAKE_TELEMETRY);
    await ruby.activateRuby();

    const firstEntry = ruby.env.PATH!.split(path.delimiter)[0];
    assert.match(firstEntry, /ruby-lsp\/exe$/);

    configStub.restore();
  }).timeout(10000);
});
