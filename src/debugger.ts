import path from "path";
import fs from "fs";
import { ChildProcessWithoutNullStreams, spawn } from "child_process";

import * as vscode from "vscode";

import { LOG_CHANNEL } from "./common";
import { Workspace } from "./workspace";

export class Debugger
  implements
    vscode.DebugAdapterDescriptorFactory,
    vscode.DebugConfigurationProvider
{
  private debugProcess?: ChildProcessWithoutNullStreams;
  private readonly console = vscode.debug.activeDebugConsole;
  private readonly workspaceResolver: (
    uri: vscode.Uri | undefined,
  ) => Workspace | undefined;

  constructor(
    context: vscode.ExtensionContext,
    workspaceResolver: (uri: vscode.Uri | undefined) => Workspace | undefined,
  ) {
    this.workspaceResolver = workspaceResolver;

    context.subscriptions.push(
      vscode.debug.registerDebugConfigurationProvider("ruby_lsp", this),
      vscode.debug.registerDebugAdapterDescriptorFactory("ruby_lsp", this),
    );
  }

  // This is where we start the debuggee process. We currently support launching with the debugger or attaching to a
  // process that was already booted with the debugger
  async createDebugAdapterDescriptor(
    session: vscode.DebugSession,
    _executable: vscode.DebugAdapterExecutable,
  ): Promise<vscode.DebugAdapterDescriptor | undefined> {
    if (session.configuration.request === "launch") {
      return this.spawnDebuggeeForLaunch(session);
    } else if (session.configuration.request === "attach") {
      return this.attachDebuggee();
    } else {
      return new Promise((_resolve, reject) =>
        reject(
          new Error(
            `Unknown request type: ${session.configuration.request}. Please review your launch configurations`,
          ),
        ),
      );
    }
  }

  provideDebugConfigurations?(
    _folder: vscode.WorkspaceFolder | undefined,
    _token?: vscode.CancellationToken,
  ): vscode.ProviderResult<vscode.DebugConfiguration[]> {
    return [
      {
        type: "ruby_lsp",
        name: "Debug script",
        request: "launch",
        // eslint-disable-next-line no-template-curly-in-string
        program: "ruby ${file}",
      },
      {
        type: "ruby_lsp",
        name: "Debug test",
        request: "launch",
        // eslint-disable-next-line no-template-curly-in-string
        program: "ruby -Itest ${relativeFile}",
      },
      {
        type: "ruby_lsp",
        name: "Attach debugger",
        request: "attach",
      },
    ];
  }

  // Resolve the user's debugger configuration. Here we receive what is configured in launch.json and can modify and
  // insert defaults for the user. The most important thing is making sure the Ruby environment is a part of it so that
  // we launch using the right bundle and Ruby version
  resolveDebugConfiguration?(
    folder: vscode.WorkspaceFolder | undefined,
    debugConfiguration: vscode.DebugConfiguration,
    _token?: vscode.CancellationToken,
  ): vscode.ProviderResult<vscode.DebugConfiguration> {
    const workspace = this.workspaceResolver(folder?.uri);

    if (!workspace) {
      throw new Error(
        `Couldn't find a workspace for URI: ${folder?.uri} or editor: ${vscode.window.activeTextEditor}`,
      );
    }

    if (debugConfiguration.env) {
      // If the user has their own debug launch configurations, we still need to inject the Ruby environment
      debugConfiguration.env = Object.assign(
        debugConfiguration.env,
        workspace.ruby.env,
      );
    } else {
      debugConfiguration.env = workspace.ruby.env;
    }

    const workspacePath = workspace.workspaceFolder.uri.fsPath;

    debugConfiguration.targetFolder = {
      path: workspacePath,
      name: workspace.workspaceFolder.name,
    };

    let customGemfilePath = path.join(workspacePath, ".ruby-lsp", "Gemfile");
    if (fs.existsSync(customGemfilePath)) {
      debugConfiguration.env.BUNDLE_GEMFILE = customGemfilePath;
    }

    customGemfilePath = path.join(workspacePath, ".ruby-lsp", "gems.rb");
    if (fs.existsSync(customGemfilePath)) {
      debugConfiguration.env.BUNDLE_GEMFILE = customGemfilePath;
    }

    return debugConfiguration;
  }

  // If the extension is deactivating, we need to ensure the debug process is terminated or else it may continue running
  // in the background
  dispose() {
    if (this.debugProcess) {
      this.debugProcess.kill("SIGTERM");
    }
  }

  private async attachDebuggee(): Promise<vscode.DebugAdapterDescriptor> {
    // When using attach, a process will be launched using Ruby debug and it will create a socket automatically. We have
    // to find the available sockets and ask the user which one they want to attach to
    const socketsDir = path.join("/", "tmp", "ruby-lsp-debug-sockets");
    const sockets = fs
      .readdirSync(socketsDir)
      .map((file) => file)
      .filter((file) => file.endsWith(".sock"));

    if (sockets.length === 0) {
      throw new Error(
        `No debuggee processes found. Was a socket created in ${socketsDir}?`,
      );
    }

    const selectedSocketPath = await vscode.window
      .showQuickPick(sockets, {
        placeHolder: "Select a debuggee",
        ignoreFocusOut: true,
      })
      .then((value) => {
        if (value === undefined) {
          throw new Error("No debuggee selected");
        }
        return path.join(socketsDir, value);
      });

    return new vscode.DebugAdapterNamedPipeServer(selectedSocketPath);
  }

  private spawnDebuggeeForLaunch(
    session: vscode.DebugSession,
  ): Promise<vscode.DebugAdapterDescriptor | undefined> {
    let initialMessage = "";
    let initialized = false;

    const configuration = session.configuration;
    const workspaceFolder = configuration.targetFolder;
    const cwd = workspaceFolder.path;
    const sockPath = this.socketPath(workspaceFolder.name);

    return new Promise((resolve, reject) => {
      const args = [
        "exec",
        "rdbg",
        "--open",
        "--command",
        `--sock-path=${sockPath}`,
        "--",
        configuration.program,
      ];

      LOG_CHANNEL.info(`Spawning debugger in directory ${cwd}`);
      LOG_CHANNEL.info(`   Command bundle ${args.join(" ")}`);
      LOG_CHANNEL.info(`   Environment ${JSON.stringify(configuration.env)}`);

      this.debugProcess = spawn("bundle", args, {
        shell: true,
        env: configuration.env,
        cwd,
      });

      this.debugProcess.stderr.on("data", (data) => {
        const message = data.toString();
        // Print whatever data we get in stderr in the debug console since it might be relevant for the user
        this.console.append(message);

        if (!initialized) {
          initialMessage += message;
        }

        // When stderr includes a complete wait for debugger connection message, then we're done initializing and can
        // resolve the promise. If we try to resolve earlier, VS Code will simply fail to connect
        if (
          initialMessage.includes("DEBUGGER: wait for debugger connection...")
        ) {
          initialized = true;
          resolve(new vscode.DebugAdapterNamedPipeServer(sockPath));
        }
      });

      // Anything printed by debug to stdout we want to show in the debug console
      this.debugProcess.stdout.on("data", (data) => {
        this.console.append(data.toString());
      });

      // If any errors occur in the server, we have to show that in the debug console and reject the promise
      this.debugProcess.on("error", (error) => {
        this.console.append(error.message);
        reject(error);
      });

      // If the Ruby debug exits with an exit code > 1, then an error might've occurred. The reason we don't use only
      // code zero here is because debug actually exits with 1 if the user cancels the debug session, which is not
      // actually an error
      this.debugProcess.on("exit", (code) => {
        if (code) {
          const message = `Debugger exited with status ${code}. Check the output channel for more information.`;
          this.console.append(message);
          LOG_CHANNEL.show();
          reject(new Error(message));
        }
      });
    });
  }

  // Generate a socket path so that Ruby debug doesn't have to create one for us. This makes coordination easier since
  // we always know the path to the socket
  private socketPath(workspaceName: string) {
    const socketsDir = path.join("/", "tmp", "ruby-lsp-debug-sockets");
    if (!fs.existsSync(socketsDir)) {
      fs.mkdirSync(socketsDir);
    }

    let socketIndex = 0;
    const prefix = `ruby-debug-${workspaceName}`;
    const existingSockets = fs
      .readdirSync(socketsDir)
      .map((file) => file)
      .filter((file) => file.startsWith(prefix))
      .sort();

    if (existingSockets.length > 0) {
      socketIndex =
        Number(
          /-(\d+).sock$/.exec(existingSockets[existingSockets.length - 1])![1],
        ) + 1;
    }

    return `${socketsDir}/${prefix}-${socketIndex}.sock`;
  }
}
