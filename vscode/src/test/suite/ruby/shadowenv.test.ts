import fs from "fs";
import assert from "assert";
import path from "path";
import os from "os";
import { execSync } from "child_process";

import { beforeEach, afterEach } from "mocha";
import * as vscode from "vscode";
import sinon from "sinon";

import { Shadowenv } from "../../../ruby/shadowenv";
import { WorkspaceChannel } from "../../../workspaceChannel";
import { LOG_CHANNEL, asyncExec } from "../../../common";
import { RUBY_VERSION } from "../../rubyVersion";
import * as common from "../../../common";
import { createContext, FakeContext } from "../helpers";

suite("Shadowenv", () => {
  if (os.platform() === "win32") {
    // eslint-disable-next-line no-console
    console.log("Skipping Shadowenv tests on Windows");
    return;
  }

  try {
    execSync("shadowenv --version >/dev/null 2>&1");
  } catch {
    // eslint-disable-next-line no-console
    console.log("Skipping Shadowenv tests because no `shadowenv` found");
    return;
  }

  let context: FakeContext;
  beforeEach(() => {
    context = createContext();
  });
  afterEach(() => {
    context.dispose();
  });

  let rootPath: string;
  let workspacePath: string;
  let workspaceFolder: vscode.WorkspaceFolder;
  let outputChannel: WorkspaceChannel;
  let rubyBinPath: string;
  const [major, minor, patch] = RUBY_VERSION.split(".");

  if (process.env.CI && os.platform() === "linux") {
    rubyBinPath = path.join("/", "opt", "hostedtoolcache", "Ruby", RUBY_VERSION, "x64", "bin");
  } else if (process.env.CI) {
    rubyBinPath = path.join("/", "Users", "runner", "hostedtoolcache", "Ruby", RUBY_VERSION, "arm64", "bin");
  } else {
    rubyBinPath = path.join("/", "opt", "rubies", RUBY_VERSION, "bin");
  }

  assert.ok(fs.existsSync(rubyBinPath), `Ruby bin path does not exist ${rubyBinPath}`);

  const shadowLispFile = `
    (provide "ruby" "${RUBY_VERSION}")

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
    (env/set "GEM_ROOT" "${path.dirname(rubyBinPath)}/lib/ruby/gems/${major}.${minor}.0")

    (when-let ((gem-root (env/get "GEM_ROOT")))
      (env/prepend-to-pathlist "GEM_PATH" gem-root)
      (env/prepend-to-pathlist "PATH" (path-concat gem-root "bin")))

    (let ((gem-home
          (path-concat (env/get "HOME") ".gem" (env/get "RUBY_ENGINE") "${RUBY_VERSION}")))
      (do
        (env/set "GEM_HOME" gem-home)
        (env/prepend-to-pathlist "GEM_PATH" gem-home)
        (env/prepend-to-pathlist "PATH" (path-concat gem-home "bin"))))
  `;

  beforeEach(() => {
    rootPath = fs.mkdtempSync(path.join(os.tmpdir(), "ruby-lsp-test-shadowenv-"));
    workspacePath = path.join(rootPath, "workspace");

    fs.mkdirSync(workspacePath);
    fs.mkdirSync(path.join(workspacePath, ".shadowenv.d"));

    workspaceFolder = {
      uri: vscode.Uri.from({ scheme: "file", path: workspacePath }),
      name: path.basename(workspacePath),
      index: 0,
    };
    outputChannel = new WorkspaceChannel("fake", LOG_CHANNEL);
  });

  afterEach(() => {
    fs.rmSync(rootPath, { recursive: true, force: true });
  });

  test("Finds Ruby only binary path is appended to PATH", async () => {
    await asyncExec("shadowenv trust", { cwd: workspacePath });

    fs.writeFileSync(
      path.join(workspacePath, ".shadowenv.d", "500_ruby.lisp"),
      `(env/prepend-to-pathlist "PATH" "${rubyBinPath}")`,
    );

    const shadowenv = new Shadowenv(workspaceFolder, outputChannel, context, async () => {});
    const { env, version, yjit } = await shadowenv.activate();

    assert.match(env.PATH!, new RegExp(rubyBinPath));
    assert.strictEqual(version, RUBY_VERSION);
    assert.notStrictEqual(yjit, undefined);
  });

  test("Finds Ruby on a complete shadowenv configuration", async () => {
    await asyncExec("shadowenv trust", { cwd: workspacePath });

    fs.writeFileSync(path.join(workspacePath, ".shadowenv.d", "500_ruby.lisp"), shadowLispFile);

    const shadowenv = new Shadowenv(workspaceFolder, outputChannel, context, async () => {});
    const { env, version, yjit } = await shadowenv.activate();

    assert.match(env.PATH!, new RegExp(rubyBinPath));
    assert.strictEqual(env.GEM_ROOT, `${path.dirname(rubyBinPath)}/lib/ruby/gems/${major}.${minor}.0`);
    assert.strictEqual(version, RUBY_VERSION);
    assert.notStrictEqual(yjit, undefined);
  });

  test("Untrusted workspace offers to trust it", async () => {
    fs.writeFileSync(path.join(workspacePath, ".shadowenv.d", "500_ruby.lisp"), shadowLispFile);

    const stub = sinon.stub(vscode.window, "showErrorMessage").resolves("Trust workspace" as any);

    const shadowenv = new Shadowenv(workspaceFolder, outputChannel, context, async () => {});
    const { env, version, yjit } = await shadowenv.activate();

    assert.match(env.PATH!, new RegExp(rubyBinPath));
    assert.match(env.GEM_HOME!, new RegExp(`\\.gem\\/ruby\\/${major}\\.${minor}\\.${patch}`));
    assert.strictEqual(version, RUBY_VERSION);
    assert.notStrictEqual(yjit, undefined);

    assert.ok(stub.calledOnce);

    stub.restore();
  });

  test("Deciding not to trust the workspace fails activation", async () => {
    fs.writeFileSync(path.join(workspacePath, ".shadowenv.d", "500_ruby.lisp"), shadowLispFile);

    const stub = sinon.stub(vscode.window, "showErrorMessage").resolves("Cancel" as any);

    const shadowenv = new Shadowenv(workspaceFolder, outputChannel, context, async () => {});

    await assert.rejects(async () => {
      await shadowenv.activate();
    });

    assert.ok(stub.calledOnce);

    stub.restore();
  });

  test("Warns user is shadowenv executable can't be found", async () => {
    await asyncExec("shadowenv trust", { cwd: workspacePath });

    fs.writeFileSync(path.join(workspacePath, ".shadowenv.d", "500_ruby.lisp"), shadowLispFile);

    const shadowenv = new Shadowenv(workspaceFolder, outputChannel, context, async () => {});

    // First, reject the call to `shadowenv exec`. Then resolve the call to `which shadowenv` to return nothing
    const execStub = sinon
      .stub(common, "asyncExec")
      .onFirstCall()
      .rejects(new Error("shadowenv: command not found"))
      .onSecondCall()
      .rejects(new Error("shadowenv: command not found"));

    await assert.rejects(async () => {
      await shadowenv.activate();
    });

    execStub.restore();
  });
});
