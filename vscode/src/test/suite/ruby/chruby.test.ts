/* eslint-disable no-process-env */
import fs from "fs";
import assert from "assert";
import path from "path";
import os from "os";

import { before, after } from "mocha";
import * as vscode from "vscode";

import { Chruby } from "../../../ruby/chruby";
import { WorkspaceChannel } from "../../../workspaceChannel";
import { LOG_CHANNEL } from "../../../common";

const RUBY_VERSION = "3.3.0";

// Create links to the real Ruby installations on CI and on our local machines
function createRubySymlinks(destination: string) {
  if (process.env.CI && os.platform() === "linux") {
    fs.symlinkSync(
      `/opt/hostedtoolcache/Ruby/${RUBY_VERSION}/x64/bin/ruby`,
      destination,
    );
  } else if (process.env.CI) {
    fs.symlinkSync(
      `/Users/runner/hostedtoolcache/Ruby/${RUBY_VERSION}/x64/bin/ruby`,
      destination,
    );
  } else {
    fs.symlinkSync("/opt/rubies/3.3.0/bin/ruby", destination);
  }
}

suite("Chruby", () => {
  if (os.platform() === "win32") {
    // eslint-disable-next-line no-console
    console.log("Skipping Chruby tests on Windows");
    return;
  }

  let rootPath: string;
  let workspacePath: string;
  let workspaceFolder: vscode.WorkspaceFolder;
  let outputChannel: WorkspaceChannel;

  before(() => {
    rootPath = fs.mkdtempSync(path.join(os.tmpdir(), "ruby-lsp-test-chruby-"));

    fs.mkdirSync(path.join(rootPath, "opt", "rubies", RUBY_VERSION, "bin"), {
      recursive: true,
    });

    createRubySymlinks(
      path.join(rootPath, "opt", "rubies", RUBY_VERSION, "bin", "ruby"),
    );

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

  test("Finds Ruby when .ruby-version is inside workspace", async () => {
    fs.writeFileSync(path.join(workspacePath, ".ruby-version"), RUBY_VERSION);

    const chruby = new Chruby(workspaceFolder, outputChannel);
    chruby.rubyInstallationUris = [
      vscode.Uri.file(path.join(rootPath, "opt", "rubies")),
    ];

    const { env, version, yjit } = await chruby.activate();

    assert.match(env.GEM_PATH!, /ruby\/3\.3\.0/);
    assert.match(env.GEM_PATH!, /lib\/ruby\/gems\/3\.3\.0/);
    assert.strictEqual(version, RUBY_VERSION);
    assert.notStrictEqual(yjit, undefined);
  });

  test("Finds Ruby when .ruby-version is inside on parent directories", async () => {
    fs.writeFileSync(path.join(rootPath, ".ruby-version"), RUBY_VERSION);

    const chruby = new Chruby(workspaceFolder, outputChannel);
    chruby.rubyInstallationUris = [
      vscode.Uri.file(path.join(rootPath, "opt", "rubies")),
    ];

    const { env, version, yjit } = await chruby.activate();

    assert.match(env.GEM_PATH!, /ruby\/3\.3\.0/);
    assert.match(env.GEM_PATH!, /lib\/ruby\/gems\/3\.3\.0/);
    assert.strictEqual(version, RUBY_VERSION);
    assert.notStrictEqual(yjit, undefined);
  });

  test("Prefers standard rubies over custom built ones", async () => {
    fs.mkdirSync(
      path.join(rootPath, "opt", "rubies", `${RUBY_VERSION}-custom`, "bin"),
      {
        recursive: true,
      },
    );

    createRubySymlinks(
      path.join(
        rootPath,
        "opt",
        "rubies",
        `${RUBY_VERSION}-custom`,
        "bin",
        "ruby",
      ),
    );

    fs.writeFileSync(path.join(rootPath, ".ruby-version"), RUBY_VERSION);

    const chruby = new Chruby(workspaceFolder, outputChannel);
    chruby.rubyInstallationUris = [
      vscode.Uri.file(path.join(rootPath, "opt", "rubies")),
    ];

    const { env, version, yjit } = await chruby.activate();

    assert.match(env.GEM_PATH!, /ruby\/3\.3\.0/);
    assert.match(env.GEM_PATH!, /lib\/ruby\/gems\/3\.3\.0/);
    assert.strictEqual(version, RUBY_VERSION);
    assert.notStrictEqual(yjit, undefined);
  });
});
