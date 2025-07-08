import path from "path";

import * as vscode from "vscode";

import { Workspace } from "./workspace";

interface SourceLocation {
  file: string;
  line: number;
  character?: number;
  endLine?: number;
  endCharacter?: number;
}

export async function openFile(
  telemetry: vscode.TelemetryLogger,
  workspace: Workspace | undefined,
  sourceLocation: SourceLocation,
) {
  const { file, ...location } = sourceLocation;
  const { line, character = 0, endLine = line, endCharacter = character } = location;
  const selection = new vscode.Range(line, character, endLine, endCharacter);
  const uri = vscode.Uri.parse(`file://${file}`);
  const doc = await vscode.workspace.openTextDocument(uri);

  await vscode.window.showTextDocument(doc, { selection });

  if (workspace?.lspClient?.serverVersion) {
    telemetry.logUsage("ruby_lsp.code_lens", {
      type: "counter",
      attributes: {
        label: "open_file",
        vscodemachineid: vscode.env.machineId,
      },
    });
  }
}

// Open the given URIs in the editor, which should follow this format:
// `file:///path/to/file.rb#Lstart_line,start_column-end_line,end_column`
export async function openUris(uris: string[]) {
  if (uris.length === 1) {
    await vscode.commands.executeCommand("vscode.open", vscode.Uri.parse(uris[0]));
    return;
  }

  const items: ({ uri: vscode.Uri } & vscode.QuickPickItem)[] = uris.map((uriString) => {
    const uri = vscode.Uri.parse(uriString);

    return {
      label: path.basename(uri.fsPath),
      iconPath: new vscode.ThemeIcon("go-to-file"),
      uri,
    };
  });

  const pickedFile = await vscode.window.showQuickPick(items, {
    title: "Select a file to jump to",
  });

  if (!pickedFile) {
    return;
  }

  await vscode.commands.executeCommand("vscode.open", pickedFile.uri);
}

export async function newMinitestFile() {
  const document = await vscode.workspace.openTextDocument({
    language: "ruby",
  });
  const editor = await vscode.window.showTextDocument(document, {
    preview: false,
  });

  const position = new vscode.Position(0, 0);

  await editor.insertSnippet(
    new vscode.SnippetString(
      'require "test_helper"\n\nclass $1Test < Minitest::Test\n  def test_$2\n    $3\n  end\nend\n',
    ),
    new vscode.Selection(position, position),
  );
}
