import os from "os";

import * as vscode from "vscode";

import { Workspace } from "./workspace";

const BASE_COMMAND = os.platform() === "win32" ? "ruby bin/rails" : "bin/rails";

export class Rails {
  private readonly showWorkspacePick: () => Promise<Workspace | undefined>;

  constructor(showWorkspacePick: () => Promise<Workspace | undefined>) {
    this.showWorkspacePick = showWorkspacePick;
  }

  // Runs `bin/rails generate` with the given generator (e.g.: `controller`, `model`, etc.) and the desired arguments
  async generate(generatorWithArguments: string, selectedWorkspace: Workspace | undefined) {
    const workspace = selectedWorkspace ?? (await this.showWorkspacePick());

    if (!workspace) {
      return;
    }

    const createdFiles: string[] = [];
    const command = `${BASE_COMMAND} generate ${generatorWithArguments}`;

    await vscode.window.withProgress(
      {
        location: vscode.ProgressLocation.Notification,
        title: "Running Rails generate",
      },
      async (progress) => {
        progress.report({ message: `Running "${command}"` });
        const { stdout } = await workspace.execute(command, true);

        stdout.split("\n").forEach((line) => {
          const match = /create\s*(.*\..*)/.exec(line);

          if (match) {
            createdFiles.push(match[1]);
          }
        });

        progress.report({ message: "Revealing generated files" });
        await this.revealFormattedFiles(workspace, createdFiles);
      },
    );
  }

  // Invokes `bin/rails destroy` to undo the changes made by a `generate` command
  async destroy(generatorWithArguments: string, selectedWorkspace: Workspace | undefined) {
    const workspace = selectedWorkspace ?? (await this.showWorkspacePick());

    if (!workspace) {
      return;
    }

    const deletedFiles: string[] = [];
    const command = `${BASE_COMMAND} destroy ${generatorWithArguments}`;

    await vscode.window.withProgress(
      {
        location: vscode.ProgressLocation.Notification,
        title: "Running Rails destroy",
      },
      async (progress) => {
        progress.report({ message: `Running "${command}"` });
        const { stdout } = await workspace.execute(command, true);

        stdout.split("\n").forEach((line) => {
          const match = /remove\s*(.*\..*)/.exec(line);

          if (match) {
            deletedFiles.push(match[1]);
          }
        });

        progress.report({ message: "Closing deleted files" });

        for (const file of deletedFiles) {
          await vscode.commands.executeCommand(
            "workbench.action.closeActiveEditor",
            vscode.Uri.joinPath(workspace.workspaceFolder.uri, file),
          );
        }
      },
    );
  }

  private async revealFormattedFiles(workspace: Workspace, createdFiles: string[]) {
    for (const file of createdFiles) {
      const uri = vscode.Uri.joinPath(workspace.workspaceFolder.uri, file);

      await vscode.window.showTextDocument(uri, { preview: false });
      await vscode.commands.executeCommand("editor.action.formatDocument", uri);
      await vscode.commands.executeCommand("workbench.action.files.save", uri);
    }
  }
}
