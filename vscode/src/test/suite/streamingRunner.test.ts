import * as assert from "assert";
import path from "path";
import os from "os";

import * as vscode from "vscode";
import sinon from "sinon";
import { after, afterEach, before, beforeEach } from "mocha";

import { StreamingRunner } from "../../streamingRunner";

import { createContext, FakeContext } from "./helpers";

suite("StreamingRunner", () => {
  let sandbox: sinon.SinonSandbox;
  const tempDirUri = vscode.Uri.file(path.join(os.tmpdir(), "ruby-lsp"));
  const dbUri = vscode.Uri.joinPath(tempDirUri, "test_reporter_port_db.json");
  let currentDbContents: string | undefined;
  let context: FakeContext;

  before(async () => {
    try {
      const buffer = await vscode.workspace.fs.readFile(dbUri);
      currentDbContents = buffer.toString();
    } catch {
      // Do nothing
    }
  });

  after(async () => {
    if (currentDbContents) {
      await vscode.workspace.fs.writeFile(dbUri, Buffer.from(currentDbContents));
    }
  });

  beforeEach(async () => {
    await vscode.workspace.fs.createDirectory(tempDirUri);
    sandbox = sinon.createSandbox();
    context = createContext();
  });

  afterEach(() => {
    sandbox.restore();
    context.dispose();
  });

  test("updates port DB with new values", async () => {
    const initialDb = {
      // eslint-disable-next-line @typescript-eslint/naming-convention
      "/some/path/to/project": "1234",
    };

    // Write the initial DB as if we had opened the editor previously
    await vscode.workspace.fs.writeFile(dbUri, Buffer.from(JSON.stringify(initialDb)));

    const streamingRunner = new StreamingRunner(
      context,
      () => Promise.resolve(undefined),
      () => ({}) as any as vscode.TestRun,
    );

    const newWorkspaceUri = vscode.Uri.joinPath(tempDirUri, "new_workspace");
    sandbox
      .stub(vscode.workspace, "workspaceFolders")
      .get(() => [{ uri: newWorkspaceUri, name: "new_workspace", index: 1 }]);
    await streamingRunner.activate();

    const newDbContents = await vscode.workspace.fs.readFile(dbUri);
    const newDb = JSON.parse(newDbContents.toString());

    assert.strictEqual(newDb["/some/path/to/project"], "1234");
    assert.strictEqual(newDb[newWorkspaceUri.fsPath], streamingRunner.tcpPort!.toString());
  });
});
