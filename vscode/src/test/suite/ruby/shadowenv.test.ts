/* eslint-disable no-process-env */
import fs from "fs";
import assert from "assert";
import path from "path";
import os from "os";

import { beforeEach, afterEach } from "mocha";
import * as vscode from "vscode";
import sinon from "sinon";

import { Shadowenv } from "../../../ruby/shadowenv";
import { WorkspaceChannel } from "../../../workspaceChannel";
import { LOG_CHANNEL, asyncExec } from "../../../common";

const RUBY_VERSION = "3.3.0";

suite("Shadowenv", () => {
  if (os.platform() === "win32") {
    // eslint-disable-next-line no-console
    console.log("Skipping Shadowenv tests on Windows");
    return;
  }

  let rootPath: string;
  let workspacePath: string;
  let workspaceFolder: vscode.WorkspaceFolder;
  let outputChannel: WorkspaceChannel;
  let bundleGemfileStub: sinon.SinonStub;
  let rubyBinPath: string;

  if (process.env.CI && os.platform() === "linux") {
    rubyBinPath = path.join(
      "/",
      "opt",
      "hostedtoolcache",
      "Ruby",
      RUBY_VERSION,
      "x64",
      "bin",
    );
  } else if (process.env.CI) {
    rubyBinPath = path.join(
      "/",
      "Users",
      "runner",
      "hostedtoolcache",
      "Ruby",
      RUBY_VERSION,
      "x64",
      "bin",
    );
  } else {
    rubyBinPath = path.join("/", "opt", "rubies", RUBY_VERSION, "bin");
  }

  assert.ok(
    fs.existsSync(rubyBinPath),
    `Ruby bin path does not exist ${rubyBinPath}`,
  );

  beforeEach(() => {
    rootPath = fs.mkdtempSync(path.join(os.tmpdir(), "ruby-lsp-test-chruby-"));
    workspacePath = path.join(rootPath, "workspace");

    fs.mkdirSync(workspacePath);
    fs.mkdirSync(path.join(workspacePath, ".shadowenv.d"));

    bundleGemfileStub = sinon
      .stub(vscode.workspace, "getConfiguration")
      .returns({ get: () => path.join(workspacePath, "Gemfile") } as any)!;

    workspaceFolder = {
      uri: vscode.Uri.from({ scheme: "file", path: workspacePath }),
      name: path.basename(workspacePath),
      index: 0,
    };
    outputChannel = new WorkspaceChannel("fake", LOG_CHANNEL);
  });

  afterEach(() => {
    fs.rmSync(rootPath, { recursive: true, force: true });
    bundleGemfileStub.restore();
  });

  test("Finds Ruby only binary path is appended to PATH", async () => {
    await asyncExec("shadowenv trust", { cwd: workspacePath });

    fs.writeFileSync(
      path.join(workspacePath, ".shadowenv.d", "500_ruby.lisp"),
      `(env/prepend-to-pathlist "PATH" "${rubyBinPath}")`,
    );

    const shadowenv = new Shadowenv(workspaceFolder, outputChannel);
    const { env, version, yjit } = await shadowenv.activate();

    assert.match(env.PATH!, new RegExp(rubyBinPath));
    assert.strictEqual(version, RUBY_VERSION);
    assert.notStrictEqual(yjit, undefined);
  });

  test("Finds Ruby on a complete shadowenv configuration", async () => {
    await asyncExec("shadowenv trust", { cwd: workspacePath });

    fs.writeFileSync(
      path.join(workspacePath, ".shadowenv.d", "500_ruby.lisp"),
      `(provide "ruby" "${RUBY_VERSION}")
      (when-let ((ruby-root (env/get "RUBY_ROOT")))
      (env/remove-from-pathlist "PATH" (path-concat ruby-root "bin"))
      (when-let ((gem-root (env/get "GEM_ROOT")))
        (env/remove-from-pathlist "PATH" (path-concat gem-root "bin")))
      (when-let ((gem-home (env/get "GEM_HOME")))
        (env/remove-from-pathlist "PATH" (path-concat gem-home "bin"))))

      (env/set "BUNDLE_PATH" ())
      (env/set "GEM_PATH" ())
      (env/set "GEM_HOME" ())
      (env/set "RUBYOPT" ())
      (env/set "RUBYLIB" ())

      (env/set "RUBY_ROOT" "${path.dirname(rubyBinPath)}")
      (env/prepend-to-pathlist "PATH" "${rubyBinPath}")
      (env/set "RUBY_ENGINE" "ruby")
      (env/set "RUBY_VERSION" "${RUBY_VERSION}")
      (env/set "GEM_ROOT" "${path.dirname(rubyBinPath)}/lib/ruby/gems/${RUBY_VERSION}")
      `,
    );

    const shadowenv = new Shadowenv(workspaceFolder, outputChannel);
    const { env, version, yjit } = await shadowenv.activate();

    assert.match(env.PATH!, new RegExp(rubyBinPath));
    assert.strictEqual(
      env.GEM_ROOT,
      `${path.dirname(rubyBinPath)}/lib/ruby/gems/${RUBY_VERSION}`,
    );
    assert.strictEqual(version, RUBY_VERSION);
    assert.notStrictEqual(yjit, undefined);
  });

  test("Overrides GEM_HOME and GEM_PATH if necessary", async () => {
    await asyncExec("shadowenv trust", { cwd: workspacePath });

    fs.writeFileSync(
      path.join(workspacePath, ".shadowenv.d", "500_ruby.lisp"),
      `(env/set "RUBY_ENGINE" "ruby")
       (env/set "RUBY_VERSION" "${RUBY_VERSION}")

       (env/set "GEM_HOME" "/fake/.bundle/project/${RUBY_VERSION}")
       (env/set "GEM_PATH" "/fake/.bundle/project/${RUBY_VERSION}:")
       (env/prepend-to-pathlist "PATH" "/fake/.bundle/project/${RUBY_VERSION}/bin")
       (env/prepend-to-pathlist "PATH" "${rubyBinPath}")`,
    );

    const shadowenv = new Shadowenv(workspaceFolder, outputChannel);
    const { env, version, yjit } = await shadowenv.activate();

    assert.match(env.PATH!, new RegExp(rubyBinPath));
    assert.strictEqual(env.GEM_HOME, `/fake/.bundle/project/${RUBY_VERSION}`);
    assert.strictEqual(version, RUBY_VERSION);
    assert.notStrictEqual(yjit, undefined);
  });

  test("Untrusted workspace offers to trust it", async () => {
    fs.writeFileSync(
      path.join(workspacePath, ".shadowenv.d", "500_ruby.lisp"),
      `(env/set "RUBY_ENGINE" "ruby")
       (env/set "RUBY_VERSION" "${RUBY_VERSION}")

       (env/set "GEM_HOME" "/fake/.bundle/project/${RUBY_VERSION}")
       (env/set "GEM_PATH" "/fake/.bundle/project/${RUBY_VERSION}:")
       (env/prepend-to-pathlist "PATH" "/fake/.bundle/project/${RUBY_VERSION}/bin")
       (env/prepend-to-pathlist "PATH" "${rubyBinPath}")`,
    );

    const stub = sinon
      .stub(vscode.window, "showErrorMessage")
      .resolves("Trust workspace" as any);

    const shadowenv = new Shadowenv(workspaceFolder, outputChannel);
    const { env, version, yjit } = await shadowenv.activate();

    assert.match(env.PATH!, new RegExp(rubyBinPath));
    assert.strictEqual(env.GEM_HOME, `/fake/.bundle/project/${RUBY_VERSION}`);
    assert.strictEqual(version, RUBY_VERSION);
    assert.notStrictEqual(yjit, undefined);

    assert.ok(stub.calledOnce);

    stub.restore();
  });

  test("Deciding not to trust the workspace fails activation", async () => {
    fs.writeFileSync(
      path.join(workspacePath, ".shadowenv.d", "500_ruby.lisp"),
      `(env/set "RUBY_ENGINE" "ruby")
       (env/set "RUBY_VERSION" "${RUBY_VERSION}")

       (env/set "GEM_HOME" "/fake/.bundle/project/${RUBY_VERSION}")
       (env/set "GEM_PATH" "/fake/.bundle/project/${RUBY_VERSION}:")
       (env/prepend-to-pathlist "PATH" "/fake/.bundle/project/${RUBY_VERSION}/bin")
       (env/prepend-to-pathlist "PATH" "${rubyBinPath}")`,
    );

    const stub = sinon
      .stub(vscode.window, "showErrorMessage")
      .resolves("Cancel" as any);

    const shadowenv = new Shadowenv(workspaceFolder, outputChannel);

    await assert.rejects(async () => {
      await shadowenv.activate();
    });

    assert.ok(stub.calledOnce);

    stub.restore();
  });
});
