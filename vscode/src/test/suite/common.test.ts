import * as assert from "assert";

import * as vscode from "vscode";
import sinon from "sinon";

import { featureEnabled, FEATURE_FLAGS } from "../../common";

suite("Common", () => {
  let sandbox: sinon.SinonSandbox;

  setup(() => {
    sandbox = sinon.createSandbox();
    const number = 42;
    sandbox.stub(vscode.env, "machineId").value(number.toString(16));
  });

  teardown(() => {
    sandbox.restore();
  });

  test("returns consistent results for the same rollout percentage", () => {
    const firstCall = featureEnabled("tapiocaAddon");

    for (let i = 0; i < 50; i++) {
      const result = featureEnabled("tapiocaAddon");

      assert.strictEqual(
        firstCall,
        result,
        "Feature flag should be deterministic",
      );
    }
  });

  test("maintains enabled state when increasing rollout percentage", () => {
    const stub = sandbox.stub(vscode.workspace, "getConfiguration").returns({
      get: () => {
        return { all: undefined };
      },
    } as any);

    // For the fake machine of 42 in base 16 and the name `fakeFeature`, the feature flag activation percetange is
    // 0.357. For every percetange below that, the feature should appear as disabled
    [0.25, 0.3, 0.35].forEach((percentage) => {
      (FEATURE_FLAGS as any).fakeFeature = percentage;
      assert.strictEqual(featureEnabled("fakeFeature" as any), false);
    });

    // And for every percentage above that, the feature should appear as enabled
    [0.36, 0.45, 0.55, 0.65, 0.75, 0.85, 0.9, 1].forEach((percentage) => {
      (FEATURE_FLAGS as any).fakeFeature = percentage;
      assert.strictEqual(featureEnabled("fakeFeature" as any), true);
    });

    stub.restore();
  });

  test("returns false if user opted out of specific feature", () => {
    (FEATURE_FLAGS as any).fakeFeature = 1;

    const stub = sandbox.stub(vscode.workspace, "getConfiguration").returns({
      get: () => {
        return { fakeFeature: false };
      },
    } as any);

    const result = featureEnabled("fakeFeature" as any);
    stub.restore();
    assert.strictEqual(result, false);
  });

  test("returns false if user opted out of all features", () => {
    (FEATURE_FLAGS as any).fakeFeature = 1;

    const stub = sandbox.stub(vscode.workspace, "getConfiguration").returns({
      get: () => {
        return { all: false };
      },
    } as any);

    const result = featureEnabled("fakeFeature" as any);
    stub.restore();
    assert.strictEqual(result, false);
  });

  test("returns true if user opted in to all features", () => {
    (FEATURE_FLAGS as any).fakeFeature = 0.02;

    const stub = sandbox.stub(vscode.workspace, "getConfiguration").returns({
      get: () => {
        return { all: true };
      },
    } as any);

    const result = featureEnabled("fakeFeature" as any);
    stub.restore();
    assert.strictEqual(result, true);
  });
});
