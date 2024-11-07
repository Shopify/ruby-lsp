import * as assert from "assert";

import * as vscode from "vscode";
import { CodeLens } from "vscode-languageclient/node";
import { afterEach } from "mocha";

import { TestController } from "../../testController";
import { Command } from "../../common";

import { FAKE_TELEMETRY } from "./fakeTelemetry";

suite("TestController", () => {
  const context = {
    extensionMode: vscode.ExtensionMode.Test,
    subscriptions: [],
    workspaceState: {
      get: (_name: string) => undefined,
      update: (_name: string, _value: any) => Promise.resolve(),
    },
  } as unknown as vscode.ExtensionContext;

  afterEach(() => {
    context.subscriptions.forEach((subscription) => subscription.dispose());
  });

  test("createTestItems doesn't break when there's a missing group", () => {
    const controller = new TestController(
      context,
      FAKE_TELEMETRY,
      () => undefined,
    );

    const codeLensItems: CodeLens[] = [
      {
        range: new vscode.Range(0, 0, 10, 10),
        command: {
          title: "Run",
          command: Command.RunTest,
          arguments: [
            "test/fake_test.rb",
            "test_do_something",
            "bundle exec ruby -Itest test/fake_test.rb --name FakeTest#test_do_something",
            {
              /* eslint-disable @typescript-eslint/naming-convention */
              start_line: 0,
              start_column: 0,
              end_line: 10,
              end_column: 10,
              /* eslint-enable @typescript-eslint/naming-convention */
            },
          ],
        },
        data: {
          type: "test",
          // eslint-disable-next-line @typescript-eslint/naming-convention
          group_id: 100,
          kind: "example",
        },
      },
    ];

    assert.doesNotThrow(() => {
      controller.createTestItems(codeLensItems);
    });
  });
});
