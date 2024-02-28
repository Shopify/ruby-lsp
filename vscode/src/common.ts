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
  SelectVersionManager = "rubyLsp.selectRubyVersionManager",
  ToggleFeatures = "rubyLsp.toggleFeatures",
  FormatterHelp = "rubyLsp.formatterHelp",
  RunTest = "rubyLsp.runTest",
  RunTestInTerminal = "rubyLsp.runTestInTerminal",
  DebugTest = "rubyLsp.debugTest",
  ShowSyntaxTree = "rubyLsp.showSyntaxTree",
}

export interface RubyInterface {
  error: boolean;
  versionManager?: string;
  rubyVersion?: string;
  supportsYjit?: boolean;
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

// Creates a debounced version of a function with the specified delay. If the function is invoked before the delay runs
// out, then the previous invocation of the function gets cancelled and a new one is scheduled.
//
// Example:
// ```typescript
// // Invoking debouncedFoo will only execute after a second has passed since the last of all invocations
// const debouncedFoo = debounce(this.foo.bind(this), 1000);
// ```
export function debounce(fn: (...args: any[]) => Promise<void>, delay: number) {
  let timeoutID: NodeJS.Timeout | null = null;

  return function (...args: any[]) {
    if (timeoutID) {
      clearTimeout(timeoutID);
    }

    return new Promise((resolve, reject) => {
      timeoutID = setTimeout(() => {
        fn(...args)
          .then((result) => resolve(result))
          .catch((error) => reject(error));
      }, delay);
    });
  };
}
