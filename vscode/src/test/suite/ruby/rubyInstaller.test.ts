import fs from "fs";
import assert from "assert";
import path from "path";
import os from "os";

import { before, after } from "mocha";
import * as vscode from "vscode";

import { RubyInstaller } from "../../../ruby/rubyInstaller";
import { WorkspaceChannel } from "../../../workspaceChannel";
import { LOG_CHANNEL } from "../../../common";

const RUBY_VERSION = "3.3.0";

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
    const [major, minor, _patch] = RUBY_VERSION.split(".").map(Number);
    fs.symlinkSync(
      path.join(
        "C:",
        "hostedtoolcache",
        "windows",
        "Ruby",
        RUBY_VERSION,
        "x64",
      ),
      path.join("C:", `Ruby${major}${minor}-${os.arch()}`),
    );

    fs.writeFileSync(path.join(workspacePath, ".ruby-version"), RUBY_VERSION);

    const windows = new RubyInstaller(workspaceFolder, outputChannel);
    const { env, version, yjit } = await windows.activate();

    assert.match(env.GEM_PATH!, /ruby\/3\.3\.0/);
    assert.match(env.GEM_PATH!, /lib\/ruby\/gems\/3\.3\.0/);
    assert.strictEqual(version, RUBY_VERSION);
    assert.notStrictEqual(yjit, undefined);

    fs.rmSync(path.join("C:", `Ruby${major}${minor}-${os.arch()}`), {
      recursive: true,
      force: true,
    });
  });

  test("Finds Ruby when under C:/Users/Username/RubyXY-arch", async () => {
    const [major, minor, _patch] = RUBY_VERSION.split(".").map(Number);
    fs.symlinkSync(
      path.join(
        "C:",
        "hostedtoolcache",
        "windows",
        "Ruby",
        RUBY_VERSION,
        "x64",
      ),
      path.join(os.homedir(), `Ruby${major}${minor}-${os.arch()}`),
    );

    fs.writeFileSync(path.join(workspacePath, ".ruby-version"), RUBY_VERSION);

    const windows = new RubyInstaller(workspaceFolder, outputChannel);
    const { env, version, yjit } = await windows.activate();

    assert.match(env.GEM_PATH!, /ruby\/3\.3\.0/);
    assert.match(env.GEM_PATH!, /lib\/ruby\/gems\/3\.3\.0/);
    assert.strictEqual(version, RUBY_VERSION);
    assert.notStrictEqual(yjit, undefined);

    fs.rmSync(path.join(os.homedir(), `Ruby${major}${minor}-${os.arch()}`), {
      recursive: true,
      force: true,
    });
  });
});
