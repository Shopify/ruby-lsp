import fs from "fs/promises";
import { exec } from "child_process";
import { promisify } from "util";

import * as vscode from "vscode";
import { State } from "vscode-languageclient";

export enum Command {
  Start = "rubyLsp.start",
  Stop = "rubyLsp.stop",
  Restart = "rubyLsp.restart",
  Update = "rubyLsp.update",
  ToggleExperimentalFeatures = "rubyLsp.toggleExperimentalFeatures",
  ServerOptions = "rubyLsp.serverOptions",
  ChangeRubyVersion = "rubyLsp.changeRubyVersion",
  ToggleFeatures = "rubyLsp.toggleFeatures",
  FormatterHelp = "rubyLsp.formatterHelp",
  RunTest = "rubyLsp.runTest",
  RunTestInTerminal = "rubyLsp.runTestInTerminal",
  DebugTest = "rubyLsp.debugTest",
  OpenLink = "rubyLsp.openLink",
  ShowSyntaxTree = "rubyLsp.showSyntaxTree",
}

export interface RubyInterface {
  rubyVersion?: string;
  yjitEnabled?: boolean;
}

export interface ClientInterface {
  state: State;
  formatter: string;
  serverVersion?: string;
  sendRequest<T>(
    method: string,
    param: any,
    token?: vscode.CancellationToken,
  ): Promise<T>;
}

export interface WorkspaceInterface {
  ruby: RubyInterface;
  lspClient?: ClientInterface;
  error: boolean;
}

// Event emitter used to signal that the language status items need to be refreshed
export const STATUS_EMITTER = new vscode.EventEmitter<
  WorkspaceInterface | undefined
>();

export const asyncExec = promisify(exec);
export const LSP_NAME = "Ruby LSP";
export const LOG_CHANNEL = vscode.window.createOutputChannel(LSP_NAME, {
  log: true,
});

export async function pathExists(
  path: string,
  mode = fs.constants.R_OK,
): Promise<boolean> {
  try {
    await fs.access(path, mode);
    return true;
  } catch (error: any) {
    return false;
  }
}
