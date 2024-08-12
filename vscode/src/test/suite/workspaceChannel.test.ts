import * as assert from "assert";

import * as vscode from "vscode";

import { WorkspaceChannel } from "../../workspaceChannel";

class FakeChannel {
  public readonly messages: string[] = [];

  info(message: string) {
    this.messages.push(message);
  }
}

suite("Workspace channel", () => {
  test("prepends name as a prefix", () => {
    const fakeChannel = new FakeChannel();
    const channel = new WorkspaceChannel(
      "test",
      fakeChannel as unknown as vscode.LogOutputChannel,
    );

    channel.info("hello!");
    assert.strictEqual(fakeChannel.messages.length, 1);
    assert.strictEqual(fakeChannel.messages[0], "(test) hello!");
  });
});
