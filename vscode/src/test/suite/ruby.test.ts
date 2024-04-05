import * as assert from "assert";
import * as path from "path";

import * as vscode from "vscode";
import sinon from "sinon";

import { Ruby, ManagerIdentifier } from "../../ruby";
import { WorkspaceChannel } from "../../workspaceChannel";
import { LOG_CHANNEL } from "../../common";

suite("Ruby environment activation", () => {
  let ruby: Ruby;

  test("Activate fetches Ruby information when outside of Ruby LSP", async () => {
    // eslint-disable-next-line no-process-env
    const manager = process.env.CI
      ? ManagerIdentifier.None
      : ManagerIdentifier.Chruby;

    const configStub = sinon
      .stub(vscode.workspace, "getConfiguration")
      .returns({
        get: (name: string) => {
          if (name === "rubyVersionManager") {
            return manager;
          } else if (name === "bundleGemfile") {
            return "";
          }

          return undefined;
        },
      } as unknown as vscode.WorkspaceConfiguration);

    const workspacePath = path.dirname(
      path.dirname(path.dirname(path.dirname(__dirname))),
    );

    const context = {
      extensionMode: vscode.ExtensionMode.Test,
    } as vscode.ExtensionContext;
    const outputChannel = new WorkspaceChannel("fake", LOG_CHANNEL);

    ruby = new Ruby(
      context,
      {
        uri: vscode.Uri.file(workspacePath),
        name: path.basename(workspacePath),
        index: 0,
      } as vscode.WorkspaceFolder,
      outputChannel,
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
});
