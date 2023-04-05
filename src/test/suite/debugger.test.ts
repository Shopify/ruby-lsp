import * as assert from "assert";

import * as vscode from "vscode";

import { Debugger } from "../../debugger";
import { Ruby } from "../../ruby";

suite("Debugger", () => {
  test("Provide debug configurations returns the default configs", () => {
    const context = { subscriptions: [] } as unknown as vscode.ExtensionContext;
    const ruby = { env: {} } as Ruby;
    const debug = new Debugger(context, ruby, "fake");
    const configs = debug.provideDebugConfigurations!(undefined);
    assert.deepEqual(
      [
        {
          type: "ruby_lsp",
          name: "Debug",
          request: "launch",
          // eslint-disable-next-line no-template-curly-in-string
          program: "ruby ${file}",
          env: ruby.env,
        },
        {
          type: "ruby_lsp",
          name: "Debug",
          request: "launch",
          // eslint-disable-next-line no-template-curly-in-string
          program: "ruby -Itest ${relativeFile}",
          env: ruby.env,
        },
        {
          type: "ruby_lsp",
          name: "Debug",
          request: "attach",
          env: ruby.env,
        },
      ],
      configs
    );

    debug.dispose();
  });

  test("Resolve configuration injects Ruby environment", () => {
    const context = { subscriptions: [] } as unknown as vscode.ExtensionContext;
    const ruby = { env: { bogus: "hello!" } } as unknown as Ruby;
    const debug = new Debugger(context, ruby, "fake");
    const configs: any = debug.resolveDebugConfiguration!(undefined, {
      type: "ruby_lsp",
      name: "Debug",
      request: "launch",
      // eslint-disable-next-line no-template-curly-in-string
      program: "ruby ${file}",
    });

    assert.strictEqual(ruby.env, configs.env);
    debug.dispose();
  });
});
