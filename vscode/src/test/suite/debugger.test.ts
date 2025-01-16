import * as assert from "assert";
import * as fs from "fs";
import * as path from "path";
import * as os from "os";

import * as vscode from "vscode";
import { afterEach, beforeEach } from "mocha";

import { Debugger } from "../../debugger";
import { ManagerIdentifier, Ruby } from "../../ruby";
import { Workspace } from "../../workspace";
import { WorkspaceChannel } from "../../workspaceChannel";
import { LOG_CHANNEL } from "../../common";
import { RUBY_VERSION } from "../rubyVersion";

import { FAKE_TELEMETRY, launchClient } from "./testHelpers";

suite("Debugger", () => {
  const originalSaveBeforeStart = vscode.workspace
    .getConfiguration("debug")
    .get("saveBeforeStart");

  beforeEach(async () => {
    await vscode.workspace
      .getConfiguration("debug")
      .update("saveBeforeStart", "none", true);
  });

  afterEach(async () => {
    await vscode.workspace
      .getConfiguration("debug")
      .update("saveBeforeStart", originalSaveBeforeStart, true);
  });

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
    if (process.env.CI) {
      await vscode.workspace
        .getConfiguration("rubyLsp")
        .update(
          "rubyVersionManager",
          { identifier: ManagerIdentifier.None },
          true,
        );
    }

    const tmpPath = fs.mkdtempSync(
      path.join(os.tmpdir(), "ruby-lsp-test-debugger"),
    );
    fs.writeFileSync(path.join(tmpPath, "test.rb"), "1 + 1");
    fs.writeFileSync(path.join(tmpPath, ".ruby-version"), RUBY_VERSION);
    fs.writeFileSync(
      path.join(tmpPath, "Gemfile"),
      'source "https://rubygems.org"',
    );
    fs.writeFileSync(
      path.join(tmpPath, "Gemfile.lock"),
      [
        "GEM",
        "  remote: https://rubygems.org/",
        "specs:",
        "",
        "PLATFORMS",
        "  arm64-darwin-23",
        " ruby",
        "",
        "DEPENDENCIES",
        "",
        "",
        "BUNDLED WITH",
        " 2.5.7",
      ].join("\n"),
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
    const ruby = new Ruby(
      context,
      workspaceFolder,
      outputChannel,
      FAKE_TELEMETRY,
    );
    await ruby.activateRuby();

    // We launch the client to compose the bundle and merge the environment into the Ruby object
    const client = await launchClient(
      context,
      ruby,
      workspaceFolder,
      outputChannel,
    );
    try {
      await client.stop();
      await client.dispose();
    } catch (error: any) {
      assert.fail(`Failed to stop client: ${error.message}`);
    }

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

    // so that we can clean up stubs otherwise they leak into other tests.
    await new Promise<void>((resolve) => {
      const callback = vscode.debug.onDidTerminateDebugSession((_session) => {
        debug.dispose();
        context.subscriptions.forEach((subscription) => subscription.dispose());
        fs.rmSync(tmpPath, { recursive: true, force: true });
        callback.dispose();
        resolve();
      });
    });
  }).timeout(90000);
});
