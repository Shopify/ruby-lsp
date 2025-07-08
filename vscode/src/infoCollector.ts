import * as vscode from "vscode";

import { Workspace } from "./workspace";

export async function collectRubyLspInfo(workspace: Workspace | undefined) {
  if (!workspace) {
    await vscode.window.showErrorMessage("No active Ruby workspace found.");
    return;
  }

  const lspInfo = await gatherLspInfo(workspace);
  const panel = vscode.window.createWebviewPanel("rubyLspInfo", "Ruby LSP Information", vscode.ViewColumn.One, {
    enableScripts: true,
  });

  panel.webview.html = generateRubyLspInfoReport(lspInfo);
}

async function gatherLspInfo(
  workspace: Workspace,
): Promise<Record<string, string | string[] | Record<string, unknown>>> {
  const vscodeVersion = vscode.version;
  const rubyLspExtension = vscode.extensions.getExtension("Shopify.ruby-lsp")!;
  const rubyLspExtensionVersion = rubyLspExtension.packageJSON.version;
  const rubyLspVersion = workspace.lspClient?.serverVersion ?? "Unknown";
  const rubyLspAddons =
    workspace.lspClient?.addons?.map((addon) => `${addon.name} (${addon.version ?? "unknown"})`) ?? [];
  const extensions = await getPublicExtensions();

  // Fetch rubyLsp settings
  const workspaceSettings = vscode.workspace.getConfiguration("rubyLsp", workspace.workspaceFolder);
  const userSettings = vscode.workspace.getConfiguration("rubyLsp");

  // Get only the workspace-specific settings
  const workspaceSpecificSettings: Record<string, unknown> = {};
  for (const key of Object.keys(workspaceSettings)) {
    if (workspaceSettings.inspect(key)?.workspaceValue !== undefined) {
      workspaceSpecificSettings[key] = workspaceSettings.get(key);
    }
  }

  return {
    /* eslint-disable @typescript-eslint/naming-convention */
    "VS Code Version": vscodeVersion,
    "Ruby LSP Extension Version": rubyLspExtensionVersion,
    "Ruby LSP Server Version": rubyLspVersion,
    "Ruby LSP Add-ons": rubyLspAddons,
    "Ruby Version": workspace.ruby.rubyVersion ?? "Unknown",
    "Ruby Version Manager": workspace.ruby.versionManager.identifier,
    "Installed Extensions": extensions.sort(),
    "Ruby LSP Settings": {
      Workspace: workspaceSpecificSettings,
      User: userSettings,
    },
    /* eslint-enable @typescript-eslint/naming-convention */
  };
}

async function getPublicExtensions(): Promise<string[]> {
  return vscode.extensions.all
    .filter((ext) => {
      // Filter out built-in extensions
      if (ext.packageJSON.isBuiltin) {
        return false;
      }

      // Assume if an extension doesn't have a license, it's private and should not be listed
      if (ext.packageJSON.license === "UNLICENSED" || !ext.packageJSON.license) {
        return false;
      }

      return true;
    })
    .map((ext) => `${ext.packageJSON.name} (${ext.packageJSON.version})`);
}

function generateRubyLspInfoReport(info: Record<string, string | string[] | Record<string, unknown>>): string {
  let markdown = "\n### Ruby LSP Information\n\n";

  for (const [key, value] of Object.entries(info)) {
    markdown += `#### ${key}\n\n`;
    if (Array.isArray(value)) {
      if (key === "Installed Extensions") {
        markdown += "&lt;details&gt;\n&lt;summary&gt;Click to expand&lt;/summary&gt;\n\n";
        markdown += `${value.map((val) => `- ${val}`).join("\n")}\n`;
        markdown += "&lt;/details&gt;\n";
      } else {
        markdown += `${value.map((val) => `- ${val}`).join("\n")}\n`;
      }
    } else if (typeof value === "object" && value !== null) {
      markdown += "&lt;details&gt;\n&lt;summary&gt;Click to expand&lt;/summary&gt;\n\n";
      for (const [subKey, subValue] of Object.entries(value)) {
        markdown += `##### ${subKey}\n\n`;
        markdown += `\`\`\`json\n${JSON.stringify(subValue, null, 2)}\n\`\`\`\n\n`;
      }
      markdown += "&lt;/details&gt;\n";
    } else {
      markdown += `${value}\n`;
    }
    markdown += "\n";
  }

  const html = `
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Ruby LSP Information</title>
      <style>
        body { font-family: var(--vscode-font-family); padding: 20px; }
        h1, h2, h3, p, li { color: var(--vscode-editor-foreground); }
        pre {
          background-color: var(--vscode-textBlockQuote-background);
          padding: 16px;
          overflow-x: auto;
          position: relative;
        }
        code { font-family: var(--vscode-editor-font-family); }
        #copyButton {
          position: absolute;
          top: 5px;
          right: 5px;
          background-color: var(--vscode-button-background);
          color: var(--vscode-button-foreground);
          border: none;
          padding: 5px 10px;
          cursor: pointer;
        }
        #copyButton:hover { background-color: var(--vscode-button-hoverBackground); }
      </style>
    </head>
    <body>
      <h1>Ruby LSP Information</h1>
      <p>Please copy the content below and paste it into the issue you're opening:</p>
      <pre><button id="copyButton">Copy</button><code id="diagnosticContent">${markdown}</code></pre>
      <script>
        const copyButton = document.getElementById('copyButton');
        const diagnosticContent = document.getElementById('diagnosticContent');

        copyButton.addEventListener('click', () => {
          const range = document.createRange();
          range.selectNode(diagnosticContent);
          window.getSelection().removeAllRanges();
          window.getSelection().addRange(range);
          document.execCommand('copy');
          window.getSelection().removeAllRanges();

          copyButton.textContent = 'Copied!';
          setTimeout(() => {
            copyButton.textContent = 'Copy';
          }, 2000);
        });
      </script>
    </body>
    </html>
  `;

  return html;
}
