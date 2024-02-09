import * as vscode from "vscode";

import { STATUS_EMITTER, WorkspaceInterface } from "./common";

interface DependenciesNode {
  getChildren(): BundlerTreeNode[] | undefined | Thenable<BundlerTreeNode[]>;
}

type BundlerTreeNode = Dependency | GemDirectoryPath | GemFilePath;

export class DependenciesTree
  implements vscode.TreeDataProvider<BundlerTreeNode>, vscode.Disposable
{
  private readonly _onDidChangeTreeData: vscode.EventEmitter<any> =
    new vscode.EventEmitter<any>();

  // eslint-disable-next-line @typescript-eslint/member-ordering
  readonly onDidChangeTreeData: vscode.Event<any> =
    this._onDidChangeTreeData.event;

  private currentWorkspace: WorkspaceInterface | undefined;
  private readonly treeView: vscode.TreeView<BundlerTreeNode>;
  private readonly workspaceListener: vscode.Disposable;

  constructor() {
    this.treeView = vscode.window.createTreeView("dependencies", {
      treeDataProvider: this,
      showCollapseAll: true,
    });

    this.workspaceListener = STATUS_EMITTER.event((workspace) => {
      if (!workspace || workspace === this.currentWorkspace) {
        return;
      }

      this.currentWorkspace = workspace;
      this.refresh();
    });
  }

  dispose(): void {
    this.workspaceListener.dispose();
    this.treeView.dispose();
  }

  getTreeItem(
    element: BundlerTreeNode,
  ): vscode.TreeItem | Thenable<vscode.TreeItem> {
    return element;
  }

  getChildren(
    element?: BundlerTreeNode | undefined,
  ): vscode.ProviderResult<BundlerTreeNode[]> {
    if (element) {
      return element.getChildren();
    } else {
      return this.fetchDependencies();
    }
  }

  refresh(): void {
    this.fetchDependencies();
    this._onDidChangeTreeData.fire(undefined);
  }

  private async fetchDependencies(): Promise<BundlerTreeNode[]> {
    if (!this.currentWorkspace) {
      return [];
    }

    const resp = (await this.currentWorkspace.lspClient?.sendRequest(
      "rubyLsp/workspace/dependencies",
      {},
    )) as [
      { name: string; version: string; path: string; dependency: boolean },
    ];

    return resp
      .sort((left, right) => {
        if (left.dependency === right.dependency) {
          // if the two dependencies are the same, sort by name
          return left.name.localeCompare(right.name);
        } else {
          // otherwise, direct dependencies sort before transitive dependencies
          return right.dependency ? 1 : -1;
        }
      })
      .map((dep) => {
        return new Dependency(dep.name, dep.version, vscode.Uri.file(dep.path));
      });
  }
}

class Dependency extends vscode.TreeItem implements DependenciesNode {
  constructor(
    name: string,
    version: string,
    public readonly resourceUri: vscode.Uri,
  ) {
    super(`${name} (${version})`, vscode.TreeItemCollapsibleState.Collapsed);
    this.contextValue = "dependency";
    this.iconPath = new vscode.ThemeIcon("ruby");
  }

  async getChildren() {
    const dir = this.resourceUri;
    const entries = await vscode.workspace.fs.readDirectory(dir);

    return entries.map(([name, type]) => {
      if (type === vscode.FileType.Directory) {
        return new GemDirectoryPath(vscode.Uri.joinPath(dir, name));
      } else {
        return new GemFilePath(vscode.Uri.joinPath(dir, name));
      }
    });
  }
}

class GemDirectoryPath extends vscode.TreeItem implements DependenciesNode {
  constructor(public readonly resourceUri: vscode.Uri) {
    super(resourceUri, vscode.TreeItemCollapsibleState.Collapsed);
    this.contextValue = "gem-directory-path";
    this.description = true;

    this.command = {
      command: "list.toggleExpand",
      title: "Toggle",
    };
  }

  async getChildren() {
    const dir = this.resourceUri;
    const entries = await vscode.workspace.fs.readDirectory(dir);

    return entries.map(([name, type]) => {
      if (type === vscode.FileType.Directory) {
        return new GemDirectoryPath(vscode.Uri.joinPath(dir, name));
      } else {
        return new GemFilePath(vscode.Uri.joinPath(dir, name));
      }
    });
  }
}

class GemFilePath extends vscode.TreeItem implements DependenciesNode {
  constructor(public readonly resourceUri: vscode.Uri) {
    super(resourceUri, vscode.TreeItemCollapsibleState.None);
    this.contextValue = "gem-file-path";
    this.description = true;

    this.command = {
      command: "vscode.open",
      title: "Open",
      arguments: [resourceUri],
    };
  }

  getChildren() {
    return undefined;
  }
}
