import * as vscode from "vscode";

import { pathToUri } from "../common";
import { Mise } from "./mise";

// Manage your Ruby environment with rv
//
// Learn more: https://github.com/spinel-coop/rv
export class Rv extends Mise {
  protected static getPossiblePaths(): vscode.Uri[] {
    return [
      pathToUri("/", "home", "linuxbrew", ".linuxbrew", "bin", "rv"),
      pathToUri("/", "usr", "local", "bin", "rv"),
      pathToUri("/", "opt", "homebrew", "bin", "rv"),
      pathToUri("/", "usr", "bin", "rv"),
    ];
  }

  protected getVersionManagerName(): string {
    return "Rv";
  }

  protected getConfigKey(): string {
    return "rubyVersionManager.rvExecutablePath";
  }

  protected getExecutionCommand(executablePath: string): string {
    return `${executablePath} ruby run --`;
  }
}
