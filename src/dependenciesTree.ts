import path from "path";

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
  private readonly subscriptions: vscode.Disposable[] = [];
  private gemRootFolders: Record<string, Dependency | undefined> = {};
  private currentVisibleItem: GemFilePath | undefined;

  constructor() {
    this.treeView = vscode.window.createTreeView("dependencies", {
      treeDataProvider: this,
      showCollapseAll: true,
    });

    this.subscriptions.push(
      STATUS_EMITTER.event(this.workspaceDidChange.bind(this)),
      vscode.window.onDidChangeActiveTextEditor(
        this.activeEditorDidChange.bind(this),
      ),
      this.treeView.onDidChangeVisibility(
        this.treeVisibilityDidChange.bind(this),
      ),
    );
  }

  dispose(): void {
    this.subscriptions.forEach((item) => item.dispose());
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

  getParent(element: BundlerTreeNode): vscode.ProviderResult<BundlerTreeNode> {
    const parentUri = vscode.Uri.joinPath(element.resourceUri, "..");
    const rootPath = path.parse(parentUri.path).root;

    if (parentUri.path === rootPath) {
      return undefined;
    }

    if (element instanceof GemDirectoryPath || element instanceof GemFilePath) {
      // Look up the parent in the cache of gem root folders. This allows us
      // to stop the directory tree traversal at some gem root folder.
      const dependency = this.gemRootFolders[parentUri.toString()];

      if (dependency) {
        return dependency;
      } else {
        return new GemDirectoryPath(parentUri);
      }
    } else {
      return undefined;
    }
  }

  private refresh(): void {
    this.fetchDependencies();
    this._onDidChangeTreeData.fire(undefined);
  }

  private workspaceDidChange(workspace: WorkspaceInterface | undefined): void {
    if (!workspace || workspace === this.currentWorkspace) {
      return;
    }

    this.currentWorkspace = workspace;
    this.refresh();
  }

  private activeEditorDidChange(editor: vscode.TextEditor | undefined): void {
    const uri = editor?.document.uri;

    if (!uri) {
      return;
    }

    // In case the tree view is not visible, we need to remember the current
    // visible item, so that we can reveal it when the tree view becomes visible.
    this.currentVisibleItem = new GemFilePath(uri);

    if (this.treeView.visible) {
      this.revealElement(this.currentVisibleItem);
    }
  }

  private treeVisibilityDidChange(
    event: vscode.TreeViewVisibilityChangeEvent,
  ): void {
    if (this.currentVisibleItem && event.visible) {
      this.revealElement(this.currentVisibleItem);
    }
  }

  private revealElement(element: BundlerTreeNode): void {
    const autoReveal: boolean | undefined = vscode.workspace
      .getConfiguration("explorer")
      .get("autoReveal");

    if (autoReveal) {
      this.treeView.reveal(element, {
        select: true,
        focus: false,
        expand: true,
      });
    }

    this.currentVisibleItem = undefined;
  }

  private async fetchDependencies(): Promise<BundlerTreeNode[]> {
    this.gemRootFolders = {};

    if (!this.currentWorkspace) {
      return [];
    }

    const resp = (await this.currentWorkspace.lspClient?.sendRequest(
      "rubyLsp/workspace/dependencies",
      {},
    )) as [
      { name: string; version: string; path: string; dependency: boolean },
    ];

    const dependencies = resp
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
        const uri = vscode.Uri.file(dep.path);
        const dependency = new Dependency(dep.name, dep.version, uri);
        this.gemRootFolders[uri.toString()] = dependency;
        return dependency;
      });

    dependencies.forEach((dep) => {
      this.gemRootFolders[dep.resourceUri.toString()] = dep;
    });

    return dependencies;
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
