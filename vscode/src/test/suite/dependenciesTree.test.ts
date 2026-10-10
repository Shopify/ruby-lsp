import assert from "assert";

import * as vscode from "vscode";

import { DependenciesTree } from "../../dependenciesTree";

type DependenciesTreeTestAccess = {
  activeEditorDidChange(editor: vscode.TextEditor): Promise<void>;
  currentVisibleItem?: vscode.TreeItem & { resourceUri: vscode.Uri };
};

suite("DependenciesTree", () => {
  test("clears the pending reveal when the active editor is untitled", async () => {
    const tree = new DependenciesTree();
    const internals = tree as unknown as DependenciesTreeTestAccess;

    try {
      await internals.activeEditorDidChange({
        document: { uri: vscode.Uri.file("/tmp/example.rb") },
      } as vscode.TextEditor);
      await internals.activeEditorDidChange({
        document: { uri: vscode.Uri.parse("untitled:Untitled-1") },
      } as vscode.TextEditor);

      assert.strictEqual(internals.currentVisibleItem, undefined);
    } finally {
      tree.dispose();
    }
  });

  test("tracks a file editor in the dependencies tree", async () => {
    const tree = new DependenciesTree();
    const internals = tree as unknown as DependenciesTreeTestAccess;
    const uri = vscode.Uri.file("/tmp/example.rb");

    try {
      await internals.activeEditorDidChange({ document: { uri } } as vscode.TextEditor);

      assert.strictEqual(internals.currentVisibleItem?.resourceUri.toString(), uri.toString());
    } finally {
      tree.dispose();
    }
  });
});
