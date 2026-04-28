import fs from "fs";
import assert from "assert";
import path from "path";
import os from "os";

import { beforeEach, afterEach } from "mocha";
import * as vscode from "vscode";
import sinon from "sinon";

import { Shadowenv, UntrustedWorkspaceError } from "../../../ruby/shadowenv";
import { WorkspaceChannel } from "../../../workspaceChannel";
import { LOG_CHANNEL } from "../../../common";
import * as common from "../../../common";
import { ActivationResult, NonReportableError } from "../../../ruby/versionManager";
import { createContext, FakeContext } from "../helpers";

// Typed view over the private method we need to stub. Kept in one place so the cast doesn't leak into each test.
type ShadowenvStub = { runEnvActivationScript: (command: string) => Promise<ActivationResult> };
type ActivationBehavior = ActivationResult | Error;

suite("Shadowenv", () => {
  let rootPath: string;
  let workspacePath: string;
  let workspaceFolder: vscode.WorkspaceFolder;
  let outputChannel: WorkspaceChannel;
  let context: FakeContext;
  let sandbox: sinon.SinonSandbox;
  const FAKE_ACTIVATION: ActivationResult = {
    env: { PATH: "/fake/ruby/bin:/usr/bin", GEM_ROOT: "/fake/gem/root" },
    yjit: true,
    version: "3.3.5",
    gemPath: ["/fake/gem/path"],
  };

  function stubActivation(behaviors: ActivationBehavior[]): sinon.SinonStub {
    const stub = sandbox.stub(Shadowenv.prototype as unknown as ShadowenvStub, "runEnvActivationScript");

    behaviors.forEach((behavior, i) => {
      if (behavior instanceof Error) {
        stub.onCall(i).rejects(behavior);
      } else {
        stub.onCall(i).resolves(behavior);
      }
    });

    return stub;
  }

  function expectNonReportable(error: Error, messagePattern: RegExp): boolean {
    assert.ok(error instanceof NonReportableError);
    assert.match(error.message, messagePattern);
    return true;
  }

  beforeEach(() => {
    sandbox = sinon.createSandbox();
    context = createContext();

    rootPath = fs.mkdtempSync(path.join(os.tmpdir(), "ruby-lsp-test-shadowenv-"));
    workspacePath = path.join(rootPath, "workspace");
    fs.mkdirSync(workspacePath);
    fs.mkdirSync(path.join(workspacePath, ".shadowenv.d"));

    workspaceFolder = {
      uri: vscode.Uri.file(workspacePath),
      name: path.basename(workspacePath),
      index: 0,
    };
    outputChannel = new WorkspaceChannel("fake", LOG_CHANNEL);
  });

  afterEach(() => {
    sandbox.restore();
    context.dispose();
    fs.rmSync(rootPath, { recursive: true, force: true });
  });

  test("Throws when .shadowenv.d is missing from the workspace", async () => {
    fs.rmSync(path.join(workspacePath, ".shadowenv.d"), { recursive: true, force: true });

    await assert.rejects(
      () => new Shadowenv(workspaceFolder, outputChannel, context, async () => {}).activate(),
      (error: Error) => expectNonReportable(error, /no \.shadowenv\.d directory was found/),
    );
  });

  test("Invokes `shadowenv exec -- ruby` and strips BUNDLE_GEMFILE coming from shadowenv", async () => {
    const originalBundleGemfile = process.env.BUNDLE_GEMFILE;
    process.env.BUNDLE_GEMFILE = "/from/process/env/Gemfile";

    try {
      const stub = stubActivation([
        {
          ...FAKE_ACTIVATION,
          env: { ...FAKE_ACTIVATION.env, PATH: "/fake/ruby/bin", BUNDLE_GEMFILE: "/from/shadowenv/Gemfile" },
        },
      ]);

      const { env, version, yjit, gemPath } = await new Shadowenv(
        workspaceFolder,
        outputChannel,
        context,
        async () => {},
      ).activate();

      assert.ok(stub.calledOnce);
      assert.match(stub.firstCall.args[0] as string, /shadowenv exec -- ruby$/);
      // Shadowenv's BUNDLE_GEMFILE must not leak into the final env; the server needs to control this value
      assert.notStrictEqual(env.BUNDLE_GEMFILE, "/from/shadowenv/Gemfile");
      assert.strictEqual(env.BUNDLE_GEMFILE, "/from/process/env/Gemfile");
      assert.strictEqual(env.PATH, "/fake/ruby/bin");
      assert.strictEqual(version, "3.3.5");
      assert.strictEqual(yjit, true);
      assert.deepStrictEqual(gemPath, ["/fake/gem/path"]);
    } finally {
      if (originalBundleGemfile === undefined) {
        delete process.env.BUNDLE_GEMFILE;
      } else {
        process.env.BUNDLE_GEMFILE = originalBundleGemfile;
      }
    }
  });

  test("Prompts to trust the workspace when shadowenv reports it is untrusted, and retries on accept", async () => {
    const activationStub = stubActivation([new Error("untrusted shadowenv program"), FAKE_ACTIVATION]);

    const showError = sandbox.stub(vscode.window, "showErrorMessage") as sinon.SinonStub;
    showError.resolves("Trust workspace");
    const execStub = sandbox.stub(common, "asyncExec").resolves({ stdout: "", stderr: "" });

    const result = await new Shadowenv(workspaceFolder, outputChannel, context, async () => {}).activate();

    assert.ok(showError.calledOnce);
    assert.ok(execStub.calledOnce);
    assert.match(execStub.firstCall.args[0], /^shadowenv trust$/);
    assert.strictEqual(activationStub.callCount, 2);
    assert.strictEqual(result.version, "3.3.5");
  });

  test("Rejects with UntrustedWorkspaceError when the user declines to trust the workspace", async () => {
    stubActivation([new Error("untrusted shadowenv program")]);

    const showError = sandbox.stub(vscode.window, "showErrorMessage") as sinon.SinonStub;
    showError.resolves("Shutdown Ruby LSP");

    await assert.rejects(
      () => new Shadowenv(workspaceFolder, outputChannel, context, async () => {}).activate(),
      UntrustedWorkspaceError,
    );
    assert.ok(showError.calledOnce);
  });

  test("Reports a PATH-related error when the shadowenv executable cannot be found", async () => {
    stubActivation([new Error("spawn shadowenv ENOENT")]);
    const execStub = sandbox.stub(common, "asyncExec").rejects(new Error("shadowenv: command not found"));

    await assert.rejects(
      () => new Shadowenv(workspaceFolder, outputChannel, context, async () => {}).activate(),
      (error: Error) => expectNonReportable(error, /Shadowenv executable not found/),
    );
    assert.ok(execStub.calledOnce);
    assert.match(execStub.firstCall.args[0], /^shadowenv --version$/);
  });

  test("Surfaces the underlying error when activation fails for a non-trust, non-missing reason", async () => {
    stubActivation([new Error("boom")]);
    const execStub = sandbox.stub(common, "asyncExec").resolves({ stdout: "shadowenv 2.1.5", stderr: "" });

    await assert.rejects(
      () => new Shadowenv(workspaceFolder, outputChannel, context, async () => {}).activate(),
      (error: Error) => expectNonReportable(error, /Failed to activate Ruby environment with Shadowenv: boom/),
    );
    assert.ok(execStub.calledOnce);
    assert.match(execStub.firstCall.args[0], /^shadowenv --version$/);
  });
});
