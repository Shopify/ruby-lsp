import path from "path";
import fs from "fs";
import { promisify } from "util";
import { exec } from "child_process";

import * as vscode from "vscode";
import {
  LanguageClientOptions,
  LanguageClient,
  Executable,
  RevealOutputChannelOn,
} from "vscode-languageclient/node";

import { Telemetry } from "./telemetry";
import { Ruby } from "./ruby";
import { StatusItem, Command } from "./status";

const LSP_NAME = "Ruby LSP";
const asyncExec = promisify(exec);

interface EnabledFeatures {
  [key: string]: boolean;
}

export default class Client {
  private client: LanguageClient | undefined;
  private context: vscode.ExtensionContext;
  private workingFolder: string;
  private clientOptions: LanguageClientOptions;
  private telemetry: Telemetry;
  private ruby: Ruby;
  private statusItem: StatusItem;
  private outputChannel = vscode.window.createOutputChannel(LSP_NAME);

  constructor(
    context: vscode.ExtensionContext,
    telemetry: Telemetry,
    ruby: Ruby
  ) {
    this.workingFolder = vscode.workspace.workspaceFolders![0].uri.fsPath;
    this.telemetry = telemetry;
    this.ruby = ruby;

    this.clientOptions = {
      documentSelector: [{ scheme: "file", language: "ruby" }],
      diagnosticCollectionName: LSP_NAME,
      outputChannel: this.outputChannel,
      revealOutputChannelOn: RevealOutputChannelOn.Never,
      initializationOptions: {
        enabledFeatures: this.listOfEnabledFeatures(),
      },
      middleware: {
        provideOnTypeFormattingEdits: async (
          document,
          position,
          ch,
          options,
          token,
          _next
        ) => {
          if (this.client) {
            const response: vscode.TextEdit[] | null =
              await this.client.sendRequest(
                "textDocument/onTypeFormatting",
                {
                  textDocument: { uri: document.uri.toString() },
                  position,
                  ch,
                  options,
                },
                token
              );

            if (!response) {
              return null;
            }

            // Find the $0 anchor to move the cursor
            const cursorPosition = response.find(
              (edit) => edit.newText === "$0"
            );

            if (!cursorPosition) {
              return response;
            }

            // Remove the edit including the $0 anchor
            response.splice(response.indexOf(cursorPosition), 1);

            const workspaceEdit = new vscode.WorkspaceEdit();
            workspaceEdit.set(document.uri, response);
            await vscode.workspace.applyEdit(workspaceEdit);

            await vscode.window.activeTextEditor!.insertSnippet(
              new vscode.SnippetString(cursorPosition.newText),
              new vscode.Selection(
                cursorPosition.range.start,
                cursorPosition.range.end
              )
            );

            return null;
          }

          return undefined;
        },
      },
    };

    this.context = context;
    this.statusItem = new StatusItem(this.context, this.ruby);
    this.registerCommands();
    this.registerAutoRestarts();
  }

  async start() {
    await vscode.window.withProgress(
      {
        location: vscode.ProgressLocation.Notification,
        title: "Setting up the bundle",
      },
      async (_progress) => {
        try {
          await this.setupCustomGemfile();
        } catch {
          // The progress dialog can't be closed by the user, so we have to guarantee that we catch errors
          vscode.window.showErrorMessage(
            "Failed to setup the bundle. \
              See [Troubleshooting](https://github.com/Shopify/vscode-ruby-lsp#troubleshooting) for instructions"
          );
        }
      }
    );

    // We need to get the environment again every time we start in case the user changed the environment manager
    const env = this.getEnv();

    const executable: Executable = {
      command: "bundle",
      args: ["exec", "ruby-lsp"],
      options: {
        cwd: this.workingFolder,
        env,
      },
    };

    this.client = new LanguageClient(
      LSP_NAME,
      { run: executable, debug: executable },
      this.clientOptions
    );

    await this.statusItem.refresh(Command.Start, this.ruby);

    this.client.onTelemetry((event) =>
      this.telemetry.sendEvent({
        ...event,
        rubyVersion: this.ruby.rubyVersion,
        yjitEnabled: this.ruby.yjitEnabled,
      })
    );
    await this.client.start();
  }

  async stop(): Promise<void> {
    if (this.client) {
      await this.statusItem.refresh(Command.Stop, this.ruby);
      return this.client.stop();
    }
  }

  async restart() {
    try {
      if (this.client?.isRunning()) {
        await this.stop();
        await this.start();
      } else {
        await this.start();
      }
    } catch (error: any) {
      this.outputChannel.appendLine(
        `Error restarting the server: ${error.message}`
      );
    }
  }

  private registerCommands() {
    this.context.subscriptions.push(
      vscode.commands.registerCommand(Command.Start, this.start.bind(this)),
      vscode.commands.registerCommand(Command.Restart, this.restart.bind(this)),
      vscode.commands.registerCommand(Command.Stop, this.stop.bind(this))
    );
  }

  private async setupCustomGemfile() {
    // If we're working on the ruby-lsp itself, we can't create a custom Gemfile or we'd be trying to activate the same
    // gem twice
    if (this.workingFolder.endsWith("ruby-lsp")) {
      return;
    }

    // Create the .ruby-lsp directory if it doesn't exist
    const rubyLspDirectory = path.join(this.workingFolder, ".ruby-lsp");

    if (!fs.existsSync(rubyLspDirectory)) {
      fs.mkdirSync(rubyLspDirectory);
    }

    // Ignore the .ruby-lsp directory automatically
    fs.writeFileSync(path.join(rubyLspDirectory, ".gitignore"), "*");

    // Generate the custom Gemfile that includes the `ruby-lsp`
    const customGemfilePath = path.join(rubyLspDirectory, "Gemfile");
    const gemfile = [
      "# This custom gemfile is automatically generated by the Ruby LSP extension.",
      "# It should be automatically git ignored, but in any case: do not commit it to your repository.",
      "",
    ];

    const gemEntry =
      'gem "ruby-lsp", require: false, group: :development, source: "https://rubygems.org"';

    // Only try to evaluate the top level Gemfile if there is one. Otherwise, we'll just create our own Gemfile
    if (fs.existsSync(path.join(this.workingFolder, "Gemfile"))) {
      gemfile.push('eval_gemfile "../Gemfile"');

      // If the `ruby-lsp` exists in the bundle, add it to the custom Gemfile commented out
      if (await this.migrateFromIncludingInBundle()) {
        gemfile.push(
          "# Uncomment the following line after following the instructions"
        );
        gemfile.push(
          "# at https://github.com/Shopify/vscode-ruby-lsp#migrating-from-bundle"
        );
        // If it is already in the bundle, add the gem commented out to avoid conflicts
        gemfile.push(`# ${gemEntry}`);
      } else {
        // If it's not a part of the bundle, add it to the custom Gemfile
        gemfile.push(gemEntry);
      }
    } else {
      // If no Gemfile exists, add the `ruby-lsp` gem to the custom Gemfile
      gemfile.push(gemEntry);
    }

    // Add an empty line at the end of the file
    gemfile.push("");

    fs.writeFileSync(customGemfilePath, gemfile.join("\n"));

    // Copy the current `Gemfile.lock` to the `.ruby-lsp` directory to make sure we're using the right versions of
    // RuboCop and related extensions. Because we do this in every initialization, we always use the latest version of
    // the Ruby LSP
    fs.cpSync(
      path.join(this.workingFolder, "Gemfile.lock"),
      path.join(this.workingFolder, ".ruby-lsp", "Gemfile.lock")
    );

    await asyncExec(`BUNDLE_GEMFILE=${customGemfilePath} bundle install`, {
      cwd: this.workingFolder,
    });
  }

  private registerAutoRestarts() {
    this.createRestartWatcher("Gemfile.lock");
    this.createRestartWatcher("**/.rubocop.yml");

    // If a configuration that affects the Ruby LSP has changed, update the client options using the latest
    // configuration and restart the server
    vscode.workspace.onDidChangeConfiguration(async (event) => {
      if (event.affectsConfiguration("rubyLsp")) {
        this.clientOptions.initializationOptions.enabledFeatures =
          this.listOfEnabledFeatures();

        // Re-activate Ruby if the version manager changed
        if (event.affectsConfiguration("rubyLsp.rubyVersionManager")) {
          await this.ruby.activateRuby();
        }

        await this.restart();
      }
    });
  }

  private createRestartWatcher(pattern: string) {
    const watcher = vscode.workspace.createFileSystemWatcher(
      new vscode.RelativePattern(this.workingFolder, pattern)
    );
    this.context.subscriptions.push(watcher);

    watcher.onDidChange(this.restart.bind(this));
    watcher.onDidCreate(this.restart.bind(this));
    watcher.onDidDelete(this.restart.bind(this));
  }

  private listOfEnabledFeatures(): string[] {
    const configuration = vscode.workspace.getConfiguration("rubyLsp");
    const features: EnabledFeatures = configuration.get("enabledFeatures")!;
    const allFeatures = Object.keys(features);

    // If enableExperimentalFeatures is true, all features are enabled
    if (configuration.get("enableExperimentalFeatures")) {
      return allFeatures;
    }

    return allFeatures.filter((key) => features[key]);
  }

  private getEnv() {
    // eslint-disable-next-line no-process-env
    const env = { ...process.env };
    const useYjit = vscode.workspace.getConfiguration("rubyLsp").get("yjit");

    Object.keys(env).forEach((key) => {
      if (key.startsWith("RUBY_GC")) {
        delete env[key];
      }
    });

    // Use our custom Gemfile to allow RuboCop and extensions to work without having to add ruby-lsp to the bundle. Note
    // that we can't do this for the ruby-lsp repository itself otherwise the gem is activated twice
    if (!this.workingFolder.endsWith("ruby-lsp")) {
      env.BUNDLE_GEMFILE = path.join(
        this.workingFolder,
        ".ruby-lsp",
        "Gemfile"
      );
    }

    if (!this.ruby.rubyVersion) {
      return env;
    }

    // Enabling YJIT only provides a performance benefit on Ruby 3.2.0 and above
    const yjitEnabled = useYjit && this.ruby.supportsYjit;

    if (!yjitEnabled) {
      return env;
    }

    // RUBYOPT may be empty or it may contain bundler paths. In the second case, we must concat to avoid accidentally
    // removing the paths from the env variable
    if (env.RUBYOPT) {
      env.RUBYOPT.concat(" --yjit");
    } else {
      env.RUBYOPT = "--yjit";
    }

    return env;
  }

  // Leave this function for a while to assist users migrating from the old version of the extension
  private async migrateFromIncludingInBundle(): Promise<boolean> {
    // When working on the Ruby LSP itself, it's always included in the bundle
    if (this.workingFolder.endsWith("ruby-lsp")) {
      return false;
    }

    try {
      // If bundle show succeeds, it means the ruby-lsp gem is a part of the bundle
      await asyncExec(
        `BUNDLE_GEMFILE=${path.join(
          this.workingFolder,
          "Gemfile"
        )} bundle show ruby-lsp`,
        {
          cwd: this.workingFolder,
        }
      );

      vscode.window.showInformationMessage(
        "The Ruby LSP no longer requires being a part of the bundle. Please follow the instructions \
         at [migrating from bundle](https://github.com/Shopify/vscode-ruby-lsp#migrating-from-bundle)"
      );
      return true;
    } catch (error) {
      // The LSP is not in the bundle, which is what we want
      return false;
    }
  }
}
