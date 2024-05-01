import * as assert from "assert";
import * as fs from "fs";
import * as path from "path";
import * as os from "os";

import * as vscode from "vscode";
import sinon from "sinon";

import { Debugger } from "../../debugger";
import { Ruby, ManagerIdentifier } from "../../ruby";
import { Workspace } from "../../workspace";
import { WorkspaceChannel } from "../../workspaceChannel";
import { LOG_CHANNEL, asyncExec } from "../../common";
import { RUBY_VERSION } from "../rubyVersion";

suite("Debugger", () => {
  test("Provide debug configurations returns the default configs", () => {
    const context = { subscriptions: [] } as unknown as vscode.ExtensionContext;
    const debug = new Debugger(context, () => {
      return undefined;
    });
    const configs = debug.provideDebugConfigurations!(undefined);
    assert.deepEqual(
      [
        {
          type: "ruby_lsp",
          name: "Debug script",
          request: "launch",
          // eslint-disable-next-line no-template-curly-in-string
          program: "ruby ${file}",
        },
        {
          type: "ruby_lsp",
          name: "Debug test",
          request: "launch",
          // eslint-disable-next-line no-template-curly-in-string
          program: "ruby -Itest ${relativeFile}",
        },
        {
          type: "ruby_lsp",
          name: "Attach debugger",
          request: "attach",
        },
      ],
      configs,
    );

    debug.dispose();
    context.subscriptions.forEach((subscription) => subscription.dispose());
  });

  test("Resolve configuration injects Ruby environment", async () => {
    const context = { subscriptions: [] } as unknown as vscode.ExtensionContext;
    const ruby = { env: { bogus: "hello!" } } as unknown as Ruby;
    const workspaceFolder = {
      name: "fake",
      uri: vscode.Uri.file("fake"),
      index: 0,
    };
    const debug = new Debugger(context, () => {
      return {
        ruby,
        workspaceFolder,
      } as Workspace;
    });
    const configs: any = await debug.resolveDebugConfiguration!(
      workspaceFolder,
      {
        type: "ruby_lsp",
        name: "Debug",
        request: "launch",
        // eslint-disable-next-line no-template-curly-in-string
        program: "ruby ${file}",
      },
    );

    assert.strictEqual(ruby.env, configs.env);
    debug.dispose();
    context.subscriptions.forEach((subscription) => subscription.dispose());
  });

  test("Resolve configuration injects Ruby environment and allows users custom environment", async () => {
    const context = { subscriptions: [] } as unknown as vscode.ExtensionContext;
    const ruby = { env: { bogus: "hello!" } } as unknown as Ruby;
    const workspaceFolder = {
      name: "fake",
      uri: vscode.Uri.file("fake"),
      index: 0,
    };
    const debug = new Debugger(context, () => {
      return {
        ruby,
        workspaceFolder,
      } as Workspace;
    });
    const configs: any = await debug.resolveDebugConfiguration!(
      workspaceFolder,
      {
        type: "ruby_lsp",
        name: "Debug",
        request: "launch",
        // eslint-disable-next-line no-template-curly-in-string
        program: "ruby ${file}",
        env: { parallel: "1" },
      },
    );

    assert.deepEqual({ parallel: "1", ...ruby.env }, configs.env);
    debug.dispose();
    context.subscriptions.forEach((subscription) => subscription.dispose());
  });

  test("Resolve configuration injects BUNDLE_GEMFILE if there's a custom bundle", async () => {
    const tmpPath = fs.mkdtempSync(path.join(os.tmpdir(), "ruby-lsp-test-"));
    fs.mkdirSync(path.join(tmpPath, ".ruby-lsp"));
    fs.writeFileSync(path.join(tmpPath, ".ruby-lsp", "Gemfile"), "hello!");

    const context = { subscriptions: [] } as unknown as vscode.ExtensionContext;
    const ruby = { env: { bogus: "hello!" } } as unknown as Ruby;
    const workspaceFolder = {
      name: "fake",
      uri: vscode.Uri.file(tmpPath),
      index: 0,
    };
    const debug = new Debugger(context, () => {
      return {
        ruby,
        workspaceFolder,
      } as Workspace;
    });
    const configs: any = await debug.resolveDebugConfiguration!(
      workspaceFolder,
      {
        type: "ruby_lsp",
        name: "Debug",
        request: "launch",
        // eslint-disable-next-line no-template-curly-in-string
        program: "ruby ${file}",
        env: { parallel: "1" },
      },
    );

    assert.deepEqual(
      {
        parallel: "1",
        ...ruby.env,
        BUNDLE_GEMFILE: vscode.Uri.joinPath(
          vscode.Uri.file(tmpPath),
          ".ruby-lsp",
          "Gemfile",
        ).fsPath,
      },
      configs.env,
    );

    debug.dispose();
    context.subscriptions.forEach((subscription) => subscription.dispose());
    fs.rmSync(tmpPath, { recursive: true, force: true });
  });

  test("Launching the debugger", async () => {
    // eslint-disable-next-line no-process-env
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
          } else if (name === "saveBeforeStart") {
            return "none";
          }

          return undefined;
        },
      } as unknown as vscode.WorkspaceConfiguration);

    const tmpPath = fs.mkdtempSync(
      path.join(os.tmpdir(), "ruby-lsp-test-debugger"),
    );
    fs.writeFileSync(path.join(tmpPath, "test.rb"), "1 + 1");
    fs.writeFileSync(path.join(tmpPath, ".ruby-version"), RUBY_VERSION);
    fs.writeFileSync(
      path.join(tmpPath, "Gemfile"),
      'source "https://rubygems.org"\ngem "debug"',
    );

    const context = {
      subscriptions: [],
      workspaceState: {
        get: () => undefined,
        update: () => undefined,
      },
    } as unknown as vscode.ExtensionContext;
    const outputChannel = new WorkspaceChannel("fake", LOG_CHANNEL);
    const workspaceFolder: vscode.WorkspaceFolder = {
      uri: vscode.Uri.file(tmpPath),
      name: path.basename(tmpPath),
      index: 0,
    };
    const ruby = new Ruby(context, workspaceFolder, outputChannel);
    await ruby.activateRuby();

    try {
      await asyncExec("bundle install", { env: ruby.env, cwd: tmpPath });
    } catch (error: any) {
      assert.fail(`Failed to bundle install: ${error.message}`);
    }

    assert.ok(fs.existsSync(path.join(tmpPath, "Gemfile.lock")));
    assert.match(
      fs.readFileSync(path.join(tmpPath, "Gemfile.lock")).toString(),
      /debug/,
    );

    const debug = new Debugger(context, () => {
      return {
        ruby,
        workspaceFolder,
      } as Workspace;
    });

    try {
      await vscode.debug.startDebugging(workspaceFolder, {
        type: "ruby_lsp",
        name: "Debug",
        request: "launch",
        program: `ruby ${path.join(tmpPath, "test.rb")}`,
      });
    } catch (error: any) {
      assert.fail(`Failed to launch debugger: ${error.message}`);
    }

    // The debugger might take a bit of time to disconnect from the editor. We need to perform cleanup when we receive
    // the termination callback or else we try to dispose of the debugger client too early, but we need to wait for that
    // so that we can clean up stubs otherwise they leak into other tests.
    await new Promise<void>((resolve) => {
      vscode.debug.onDidTerminateDebugSession((_session) => {
        configStub.restore();
        debug.dispose();
        context.subscriptions.forEach((subscription) => subscription.dispose());
        fs.rmSync(tmpPath, { recursive: true, force: true });
        resolve();
      });
    });
  }).timeout(45000);
});
