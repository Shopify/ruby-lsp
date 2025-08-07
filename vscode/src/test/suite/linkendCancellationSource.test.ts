import * as assert from "assert";

import * as vscode from "vscode";
import sinon from "sinon";
import { beforeEach, afterEach } from "mocha";

import { LinkedCancellationSource } from "../../linkedCancellationSource";

suite("LinkedCancellationSource", () => {
  let sandbox: sinon.SinonSandbox;

  beforeEach(() => {
    sandbox = sinon.createSandbox();
  });

  afterEach(() => {
    sandbox.restore();
  });

  test("isCancellationRequested", async () => {
    const cancellationSource = new vscode.CancellationTokenSource();
    const linkedCancellationSource = new LinkedCancellationSource(cancellationSource.token);
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

  test("dispose only disposes of the token source ", () => {
    const cancellationSource = new vscode.CancellationTokenSource();
    const spy = sandbox.stub();
    sandbox.stub(cancellationSource, "token").get(() => ({
      onCancellationRequested: () => {
        return { dispose: spy };
      },
      isCancellationRequested: () => false,
    }));

    const linkedCancellationSource = new LinkedCancellationSource(cancellationSource.token);

    linkedCancellationSource.dispose();
    assert.ok(spy.notCalled);
  });
});
