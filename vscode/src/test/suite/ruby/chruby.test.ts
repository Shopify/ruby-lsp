/* eslint-disable no-process-env */
import fs from "fs";
import assert from "assert";
import path from "path";
import os from "os";

import { before, after } from "mocha";
import * as vscode from "vscode";
import sinon from "sinon";

import { Chruby } from "../../../ruby/chruby";
import { WorkspaceChannel } from "../../../workspaceChannel";
import { LOG_CHANNEL } from "../../../common";
import { RUBY_VERSION } from "../../rubyVersion";

const [major, minor, _patch] = RUBY_VERSION.split(".");
const VERSION_REGEX = `${major}\\.${minor}\\.\\d+`;

// Create links to the real Ruby installations on CI and on our local machines
function createRubySymlinks(destination: string) {
  if (process.env.CI && os.platform() === "linux") {
    fs.symlinkSync(
      `/opt/hostedtoolcache/Ruby/${RUBY_VERSION}/x64/bin/ruby`,
      destination,
    );
  } else if (process.env.CI) {
    fs.symlinkSync(
      `/Users/runner/hostedtoolcache/Ruby/${RUBY_VERSION}/arm64/bin/ruby`,
      destination,
    );
  } else {
    fs.symlinkSync(`/opt/rubies/${RUBY_VERSION}/bin/ruby`, destination);
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

    const chruby = new Chruby(workspaceFolder, outputChannel, async () => {});
    chruby.rubyInstallationUris = [
      vscode.Uri.file(path.join(rootPath, "opt", "rubies")),
    ];

    const { env, version, yjit } = await chruby.activate();

    assert.match(env.GEM_PATH!, new RegExp(`ruby/${VERSION_REGEX}`));
    assert.match(env.GEM_PATH!, new RegExp(`lib/ruby/gems/${VERSION_REGEX}`));
    assert.strictEqual(version, RUBY_VERSION);
    assert.notStrictEqual(yjit, undefined);
  });

  test("Finds Ruby when .ruby-version is inside on parent directories", async () => {
    fs.writeFileSync(path.join(rootPath, ".ruby-version"), RUBY_VERSION);

    const chruby = new Chruby(workspaceFolder, outputChannel, async () => {});
    chruby.rubyInstallationUris = [
      vscode.Uri.file(path.join(rootPath, "opt", "rubies")),
    ];

    const { env, version, yjit } = await chruby.activate();

    assert.match(env.GEM_PATH!, new RegExp(`ruby/${VERSION_REGEX}`));
    assert.match(env.GEM_PATH!, new RegExp(`lib/ruby/gems/${VERSION_REGEX}`));
    assert.strictEqual(version, RUBY_VERSION);
    assert.notStrictEqual(yjit, undefined);
  });

  test("Considers any version with a suffix to be the latest", async () => {
    // chruby always considers anything with a suffix to be the latest version, even if that's not accurate. For
    // example, 3.3.0-rc1 is older than the stable 3.3.0, but running `chruby 3.3.0` will prefer the release candidate
    fs.mkdirSync(
      path.join(rootPath, "opt", "rubies", `${RUBY_VERSION}-rc1`, "bin"),
      {
        recursive: true,
      },
    );

    createRubySymlinks(
      path.join(
        rootPath,
        "opt",
        "rubies",
        `${RUBY_VERSION}-rc1`,
        "bin",
        "ruby",
      ),
    );

    fs.writeFileSync(path.join(rootPath, ".ruby-version"), RUBY_VERSION);

    const chruby = new Chruby(workspaceFolder, outputChannel, async () => {});
    chruby.rubyInstallationUris = [
      vscode.Uri.file(path.join(rootPath, "opt", "rubies")),
    ];

    const { env, yjit } = await chruby.activate();

    // Since we symlink the stable Ruby as if it were a release candidate, we cannot assert the version of gem paths
    // because those will match the stable version that is running the activation script. It is enough to verify that we
    // inserted the correct Ruby path into the PATH
    assert.match(
      env.PATH!,
      new RegExp(`\\/opt\\/rubies\\/${VERSION_REGEX}-rc1`),
    );
    assert.notStrictEqual(yjit, undefined);
    fs.rmSync(path.join(rootPath, "opt", "rubies", `${RUBY_VERSION}-rc1`), {
      recursive: true,
      force: true,
    });
  });

  test("Finds right Ruby with explicit release candidate but omitted engine", async () => {
    fs.mkdirSync(
      path.join(rootPath, "opt", "rubies", `${RUBY_VERSION}-rc1`, "bin"),
      {
        recursive: true,
      },
    );

    createRubySymlinks(
      path.join(
        rootPath,
        "opt",
        "rubies",
        `${RUBY_VERSION}-rc1`,
        "bin",
        "ruby",
      ),
    );

    fs.writeFileSync(
      path.join(rootPath, ".ruby-version"),
      `${RUBY_VERSION}-rc1`,
    );

    const chruby = new Chruby(workspaceFolder, outputChannel, async () => {});
    chruby.rubyInstallationUris = [
      vscode.Uri.file(path.join(rootPath, "opt", "rubies")),
    ];

    const { env, yjit } = await chruby.activate();

    assert.match(
      env.PATH!,
      new RegExp(`\\/opt\\/rubies\\/${VERSION_REGEX}-rc1`),
    );
    assert.notStrictEqual(yjit, undefined);
    fs.rmSync(path.join(rootPath, "opt", "rubies", `${RUBY_VERSION}-rc1`), {
      recursive: true,
      force: true,
    });
  });

  test("Considers Ruby as the default engine if missing", async () => {
    const rubyHome = path.join(rootPath, "fakehome", ".rubies");
    fs.mkdirSync(path.join(rubyHome, `ruby-${RUBY_VERSION}`, "bin"), {
      recursive: true,
    });

    createRubySymlinks(
      path.join(rubyHome, `ruby-${RUBY_VERSION}`, "bin", "ruby"),
    );

    fs.writeFileSync(path.join(rootPath, ".ruby-version"), RUBY_VERSION);

    const chruby = new Chruby(workspaceFolder, outputChannel, async () => {});
    chruby.rubyInstallationUris = [vscode.Uri.file(rubyHome)];

    const { env, version, yjit } = await chruby.activate();

    assert.match(env.PATH!, new RegExp(`/ruby-${RUBY_VERSION}/bin`));
    assert.strictEqual(version, RUBY_VERSION);
    assert.notStrictEqual(yjit, undefined);
  });

  test("Finds Ruby when extra RUBIES are configured", async () => {
    fs.writeFileSync(path.join(workspacePath, ".ruby-version"), RUBY_VERSION);

    const configStub = sinon
      .stub(vscode.workspace, "getConfiguration")
      .returns({
        get: (name: string) =>
          name === "rubyVersionManager.chrubyRubies"
            ? [path.join(rootPath, "opt", "rubies")]
            : "",
      } as any);

    const chruby = new Chruby(workspaceFolder, outputChannel, async () => {});
    configStub.restore();

    const { env, version, yjit } = await chruby.activate();

    assert.match(env.GEM_PATH!, new RegExp(`ruby/${VERSION_REGEX}`));
    assert.match(env.GEM_PATH!, new RegExp(`lib/ruby/gems/${VERSION_REGEX}`));
    assert.strictEqual(version, RUBY_VERSION);
    assert.notStrictEqual(yjit, undefined);
  });

  test("Finds Ruby when .ruby-version omits patch", async () => {
    fs.mkdirSync(
      path.join(rootPath, "opt", "rubies", `${major}.${minor}.0`, "bin"),
      {
        recursive: true,
      },
    );

    fs.writeFileSync(
      path.join(workspacePath, ".ruby-version"),
      `${major}.${minor}`,
    );

    const chruby = new Chruby(workspaceFolder, outputChannel, async () => {});
    chruby.rubyInstallationUris = [
      vscode.Uri.file(path.join(rootPath, "opt", "rubies")),
    ];

    const { env, version, yjit } = await chruby.activate();

    assert.match(env.GEM_PATH!, new RegExp(`ruby/${VERSION_REGEX}`));
    assert.match(env.GEM_PATH!, new RegExp(`lib/ruby/gems/${VERSION_REGEX}`));
    assert.strictEqual(version, RUBY_VERSION);
    assert.notStrictEqual(yjit, undefined);

    fs.rmSync(path.join(rootPath, "opt", "rubies", `${major}.${minor}.0`), {
      recursive: true,
      force: true,
    });
  });

  test("Continues searching if first directory doesn't exist for omitted patch", async () => {
    fs.mkdirSync(
      path.join(rootPath, "opt", "rubies", `${major}.${minor}.0`, "bin"),
      {
        recursive: true,
      },
    );

    fs.writeFileSync(
      path.join(workspacePath, ".ruby-version"),
      `${major}.${minor}`,
    );

    const chruby = new Chruby(workspaceFolder, outputChannel, async () => {});
    chruby.rubyInstallationUris = [
      vscode.Uri.file(path.join(rootPath, ".rubies")),
      vscode.Uri.file(path.join(rootPath, "opt", "rubies")),
    ];

    const { env, version, yjit } = await chruby.activate();

    assert.match(env.GEM_PATH!, new RegExp(`ruby/${VERSION_REGEX}`));
    assert.match(env.GEM_PATH!, new RegExp(`lib/ruby/gems/${VERSION_REGEX}`));
    assert.strictEqual(version, RUBY_VERSION);
    assert.notStrictEqual(yjit, undefined);
  });
});
