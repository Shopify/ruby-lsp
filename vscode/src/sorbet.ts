import * as vscode from "vscode";
import {
  LanguageClient,
  ServerOptions,
  LanguageClientOptions,
  RevealOutputChannelOn,
} from "vscode-languageclient/node";

import { WorkspaceChannel } from "./workspaceChannel";
import { Ruby } from "./ruby";

// Experimental Sorbet client to be used along with the Ruby LSP
// It's turned off if official Sorbet extension is enabled
//
// TODO:
// - Automatic restarts when sorbet/config changes
// - Allow starting, stopping and restarting the Sorbet client separately
// - Allow automatic restarts to target a specific client (so that we don't have to restart Sorbet on a rubocop.yml
// change)
// - Report Sorbet status (have the server send WorkDoneProgress notifications instead of using a custom built status
// bar)
export default class SorbetClient extends LanguageClient {
  constructor(
    ruby: Ruby,
    workspaceFolder: vscode.WorkspaceFolder,
    outputChannel: WorkspaceChannel,
    bundleArgs: string[] = ["exec", "srb", "tc", "--lsp"],
  ) {
    const serverOptions: ServerOptions = {
      command: "bundle",
      args: bundleArgs,
      options: {
        cwd: workspaceFolder.uri.fsPath,
        env: ruby.env,
        shell: true,
      },
    };

    const clientOptions: LanguageClientOptions = {
      documentSelector: [
        { language: "ruby", pattern: `${workspaceFolder.uri.fsPath}/**/*` },
      ],
      workspaceFolder,
      diagnosticCollectionName: "sorbet",
      outputChannel,
      revealOutputChannelOn: RevealOutputChannelOn.Never,
    };

    super("sorbet", serverOptions, clientOptions);
  }
}
