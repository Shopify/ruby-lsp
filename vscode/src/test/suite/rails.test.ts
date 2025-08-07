import * as assert from "assert";
import os from "os";
import path from "path";

import * as vscode from "vscode";
import sinon from "sinon";
import { beforeEach, afterEach } from "mocha";

import { Rails } from "../../rails";
import { Workspace } from "../../workspace";

const BASE_COMMAND = os.platform() === "win32" ? "ruby bin/rails" : "bin/rails";

suite("Rails", () => {
  const workspacePath = path.dirname(path.dirname(path.dirname(path.dirname(__dirname))));
  const workspaceUri = vscode.Uri.file(workspacePath);
  const workspaceFolder: vscode.WorkspaceFolder = {
    uri: workspaceUri,
    name: path.basename(workspaceUri.fsPath),
    index: 0,
  };

  let sandbox: sinon.SinonSandbox;

  beforeEach(() => {
    sandbox = sinon.createSandbox();
  });

  afterEach(() => {
    sandbox.restore();
  });

  test("generate", async () => {
    const executeStub = sandbox.stub();
    const workspace = {
      workspaceFolder,
      execute: executeStub.resolves({
        stdout: "create db/migrate/20210901123456_create_users.rb\ncreate app/models/user.rb\n",
      }),
    } as unknown as Workspace;

    const showDocumentStub = sandbox.stub(vscode.window, "showTextDocument");
    sandbox.stub(vscode.commands, "executeCommand");

    const selectedWorkspace = undefined;
    const rails = new Rails(() => Promise.resolve(workspace));
    await rails.generate("model User name:string", selectedWorkspace);

    assert.ok(executeStub.calledOnceWithExactly(`${BASE_COMMAND} generate model User name:string`, true));

    assert.ok(
      showDocumentStub
        .getCall(0)
        .calledWithExactly(vscode.Uri.joinPath(workspaceUri, "db/migrate/20210901123456_create_users.rb"), {
          preview: false,
        }),
    );
    assert.ok(
      showDocumentStub
        .getCall(1)
        .calledWithExactly(vscode.Uri.joinPath(workspaceUri, "app/models/user.rb"), { preview: false }),
    );
  });

  test("destroy", async () => {
    const executeStub = sandbox.stub();
    const workspace = {
      workspaceFolder,
      execute: executeStub.resolves({
        stdout: "remove db/migrate/20210901123456_create_users.rb\nremove app/models/user.rb\n",
      }),
    } as unknown as Workspace;

    const executeCommandStub = sandbox.stub(vscode.commands, "executeCommand");

    const selectedWorkspace = undefined;
    const rails = new Rails(() => Promise.resolve(workspace));
    await rails.destroy("model User name:string", selectedWorkspace);

    assert.ok(executeStub.calledOnceWithExactly(`${BASE_COMMAND} destroy model User name:string`, true));

    assert.ok(
      executeCommandStub
        .getCall(0)
        .calledWithExactly(
          "workbench.action.closeActiveEditor",
          vscode.Uri.joinPath(workspaceUri, "db/migrate/20210901123456_create_users.rb"),
        ),
    );
    assert.ok(
      executeCommandStub
        .getCall(1)
        .calledWithExactly(
          "workbench.action.closeActiveEditor",
          vscode.Uri.joinPath(workspaceUri, "app/models/user.rb"),
        ),
    );
  });
});
