import path from "path";

import * as vscode from "vscode";

import { Workspace } from "./workspace";

class ProfileView {
  private readonly panel: vscode.WebviewPanel;

  constructor(fileName: string, profile: any) {
    this.panel = vscode.window.createWebviewPanel(
      ProfileTaskProvider.TaskType,
      `Profile results ${fileName}`,
      vscode.ViewColumn.One,
      {},
    );

    this.generateHtml(fileName, profile);
    this.panel.onDidDispose(() => {
      this.panel.dispose();
    });
  }

  reveal() {
    this.panel.reveal();
  }

  private generateHtml(file: string, profile: any) {
    this.panel.webview.html = `
      <!DOCTYPE html>
			<html lang="en">
			<head>
				<meta charset="UTF-8">
				<meta name="viewport" content="width=device-width, initial-scale=1.0">
				<title>Profile results ${file}</title>
			</head>
			<body>
				<h1>Results</h1>
        ${profile.toString()}
			</body>
			</html>`;
  }
}

class ProfileTaskTerminal implements vscode.Pseudoterminal {
  readonly writeEmitter = new vscode.EventEmitter<string>();
  onDidWrite: vscode.Event<string> = this.writeEmitter.event;
  closeEmitter = new vscode.EventEmitter<number>();
  onDidClose?: vscode.Event<number> = this.closeEmitter.event;

  private readonly workspace: Workspace | undefined;

  constructor(workspace: Workspace | undefined) {
    this.workspace = workspace;
  }

  async open(_initialDimensions: vscode.TerminalDimensions | undefined) {
    if (!this.workspace) {
      this.writeEmitter.fire("No workspace found\r\n");
      this.closeEmitter.fire(1);
      return;
    }

    const currentFile = vscode.window.activeTextEditor?.document.uri.fsPath;

    if (!currentFile) {
      this.writeEmitter.fire("No file opened in the editor to profile\r\n");
      this.closeEmitter.fire(1);
      return;
    }

    this.writeEmitter.fire(`Profiling ${currentFile}...\r\n`);

    const workspaceUri = this.workspace.workspaceFolder.uri;
    const profileUri = vscode.Uri.joinPath(workspaceUri, "profile.json");
    const { stderr } = await this.workspace.execute(
      `vernier run --output ${profileUri.fsPath} -- ruby ${currentFile}`,
    );

    try {
      const profile = await vscode.workspace.fs.readFile(profileUri);
      this.writeEmitter.fire(
        "Successfully profiled. Generating visualization...\r\n",
      );

      const profileView = new ProfileView(path.basename(currentFile), profile);
      this.closeEmitter.fire(0);
      profileView.reveal();
    } catch (error) {
      this.writeEmitter.fire(
        `An error occurred while profiling (press any key to close):\r\n ${stderr}\r\n`,
      );
      this.closeEmitter.fire(1);
    }
  }

  close(): void {}
}

export class ProfileTaskProvider implements vscode.TaskProvider {
  static TaskType = "ruby_lsp_profile";

  private readonly currentActiveWorkspace: (
    activeEditor?: vscode.TextEditor,
  ) => Workspace | undefined;

  constructor(
    currentActiveWorkspace: (
      activeEditor?: vscode.TextEditor,
    ) => Workspace | undefined,
  ) {
    this.currentActiveWorkspace = currentActiveWorkspace;
  }

  provideTasks(
    _token: vscode.CancellationToken,
  ): vscode.ProviderResult<vscode.Task[]> {
    return [
      new vscode.Task(
        { type: ProfileTaskProvider.TaskType },
        vscode.TaskScope.Workspace,
        "Profile current Ruby file",
        "ruby_lsp",
      ),
    ];
  }

  resolveTask(
    task: vscode.Task,
    _token: vscode.CancellationToken,
  ): vscode.ProviderResult<vscode.Task> {
    const workspace = this.currentActiveWorkspace();

    return new vscode.Task(
      task.definition,
      vscode.TaskScope.Workspace,
      "Profile current Ruby file",
      "ruby_lsp",
      new vscode.CustomExecution((): Promise<vscode.Pseudoterminal> => {
        return Promise.resolve(new ProfileTaskTerminal(workspace));
      }),
    );
  }
}
