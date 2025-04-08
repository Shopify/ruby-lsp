import * as assert from "assert";

import * as vscode from "vscode";

import { LinkedCancellationSource } from "../../linkedCancellationSource";

suite("LinkedCancellationSource", () => {
  test("isCancellationRequested", async () => {
    const cancellationSource = new vscode.CancellationTokenSource();
    const linkedCancellationSource = new LinkedCancellationSource(
      cancellationSource.token,
    );
    let callbackCalled = false;

    await new Promise<void>((resolve) => {
      linkedCancellationSource.onCancellationRequested(() => {
        callbackCalled = true;
        resolve();
      });

      cancellationSource.cancel();
    });

    assert.ok(linkedCancellationSource.isCancellationRequested());
    assert.ok(callbackCalled);
  });
});
