/* eslint-disable no-process-env */
import * as assert from "assert";
import * as path from "path";

import * as vscode from "vscode";
import sinon from "sinon";

import { Ruby, ManagerIdentifier } from "../../ruby";
import { WorkspaceChannel } from "../../workspaceChannel";
import { LOG_CHANNEL } from "../../common";

suite("Ruby environment activation", () => {
  const workspacePath = path.dirname(
    path.dirname(path.dirname(path.dirname(__dirname))),
  );
  const workspaceFolder: vscode.WorkspaceFolder = {
    uri: vscode.Uri.file(workspacePath),
    name: path.basename(workspacePath),
    index: 0,
  };

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

    const context = {
      extensionMode: vscode.ExtensionMode.Test,
    } as vscode.ExtensionContext;
    const outputChannel = new WorkspaceChannel("fake", LOG_CHANNEL);

    const ruby = new Ruby(context, workspaceFolder, outputChannel);
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

    const context = {
      extensionMode: vscode.ExtensionMode.Test,
    } as vscode.ExtensionContext;
    const outputChannel = new WorkspaceChannel("fake", LOG_CHANNEL);

    const ruby = new Ruby(context, workspaceFolder, outputChannel);

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
});
