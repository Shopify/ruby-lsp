import fs from "fs";
import assert from "assert";
import path from "path";
import os from "os";

import sinon from "sinon";
import { before, after, beforeEach, afterEach } from "mocha";
import * as vscode from "vscode";

import * as common from "../../../common";
import { RubyInstaller } from "../../../ruby/rubyInstaller";
import { WorkspaceChannel } from "../../../workspaceChannel";
import { LOG_CHANNEL } from "../../../common";
import { RUBY_VERSION, VERSION_REGEX } from "../../rubyVersion";
import { ACTIVATION_SEPARATOR } from "../../../ruby/versionManager";
import { createRubySymlinks, createContext, FakeContext } from "../helpers";

suite("RubyInstaller", () => {
  if (os.platform() !== "win32") {
    // eslint-disable-next-line no-console
    console.log("This test can only run on Windows");
    return;
  }

  let rootPath: string;
  let workspacePath: string;
  let workspaceFolder: vscode.WorkspaceFolder;
  let outputChannel: WorkspaceChannel;
  let context: FakeContext;
  let sandbox: sinon.SinonSandbox;

  beforeEach(() => {
    sandbox = sinon.createSandbox();
    // eslint-disable-next-line no-process-env
    if (process.env.CI) {
      createRubySymlinks();
    }
    context = createContext();
  });

  afterEach(() => {
    sandbox.restore();
    context.dispose();
  });

  before(() => {
    rootPath = fs.mkdtempSync(path.join(os.tmpdir(), "ruby-lsp-test-"));

    workspacePath = path.join(rootPath, "workspace");
    fs.mkdirSync(workspacePath);

    workspaceFolder = {
      uri: vscode.Uri.from({ scheme: "file", path: workspacePath }),
      name: path.basename(workspacePath),
      index: 0,
    };
    outputChannel = new WorkspaceChannel("fake", LOG_CHANNEL);
  });

  after(() => {
    fs.rmSync(rootPath, { recursive: true, force: true });
  });

  test("Finds Ruby when under C:/RubyXY-arch", async () => {
    fs.writeFileSync(path.join(workspacePath, ".ruby-version"), RUBY_VERSION);

    const windows = new RubyInstaller(
      workspaceFolder,
      outputChannel,
      context,
      async () => {},
    );
    const { env, version, yjit } = await windows.activate();

    assert.match(env.GEM_PATH!, new RegExp(`ruby\\\\${VERSION_REGEX}`));
    assert.match(
      env.GEM_PATH!,
      new RegExp(`lib\\\\ruby\\\\gems\\\\${VERSION_REGEX}`),
    );
    assert.strictEqual(version, RUBY_VERSION);
    assert.notStrictEqual(yjit, undefined);
  });

  test("Finds Ruby when under C:/Users/Username/RubyXY-arch", async () => {
    fs.writeFileSync(path.join(workspacePath, ".ruby-version"), RUBY_VERSION);

    const windows = new RubyInstaller(
      workspaceFolder,
      outputChannel,
      context,
      async () => {},
    );
    const { env, version, yjit } = await windows.activate();

    assert.match(env.GEM_PATH!, new RegExp(`ruby\\\\${VERSION_REGEX}`));
    assert.match(
      env.GEM_PATH!,
      new RegExp(`lib\\\\ruby\\\\gems\\\\${VERSION_REGEX}`),
    );
    assert.strictEqual(version, RUBY_VERSION);
    assert.notStrictEqual(yjit, undefined);
  });

  test("Doesn't set the shell when invoking activation script", async () => {
    fs.writeFileSync(path.join(workspacePath, ".ruby-version"), RUBY_VERSION);

    const windows = new RubyInstaller(
      workspaceFolder,
      outputChannel,
      context,
      async () => {},
    );
    const result = ["/fake/dir", "/other/fake/dir", true, RUBY_VERSION].join(
      ACTIVATION_SEPARATOR,
    );
    const execStub = sandbox.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: result,
    });

    await windows.activate();

    assert.strictEqual(execStub.callCount, 1);
    const callArgs = execStub.getCall(0).args;
    assert.strictEqual(callArgs[1]?.shell, undefined);
  });

  test("Normalizes long file formats to back slashes", async () => {
    fs.writeFileSync(path.join(workspacePath, ".ruby-version"), RUBY_VERSION);

    const windows = new RubyInstaller(
      workspaceFolder,
      outputChannel,
      context,
      async () => {},
    );
    const result = [
      "//?/C:/Ruby32/gems",
      "//?/C:/Ruby32/default_gems",
      true,
      RUBY_VERSION,
    ].join(ACTIVATION_SEPARATOR);
    sandbox.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: result,
    });

    const { gemPath } = await windows.activate();

    assert.deepStrictEqual(gemPath, [
      "\\\\?\\C:\\Ruby32\\default_gems",
      "\\\\?\\C:\\Ruby32\\gems",
    ]);
  });
});
