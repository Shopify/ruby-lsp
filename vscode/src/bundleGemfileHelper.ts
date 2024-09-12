import path from "path";
import * as vscode from "vscode";

function expandEnvVariables(filepath: string): string {
  return filepath.replace(/\$\{(\w+)\}|\$(\w+)/g, (match: string, p1: string, p2: string): string => {
    const envVar = p1 || p2; // Use either ${VAR} or $VAR syntax
    return process.env[envVar] || match; // Replace with env var if it exists, else keep original
  });
}


export function getCustomBundleGemfile(workspaceFolder: vscode.WorkspaceFolder): string | undefined {
  const customBundleGemfile: string = vscode.workspace
    .getConfiguration("rubyLsp")
    .get("bundleGemfile")!;

  const expandedPath = expandEnvVariables(customBundleGemfile);

  if (expandedPath.length > 0) {
    return path.isAbsolute(expandedPath)
      ? expandedPath
      : path.resolve(path.join(workspaceFolder.uri.fsPath, expandedPath));
  }
  return undefined;
}
