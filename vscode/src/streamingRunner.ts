import { spawn } from "child_process";
import net from "net";

import * as rpc from "vscode-jsonrpc/node";
import * as vscode from "vscode";

import { Workspace } from "./workspace";
import { LinkedCancellationSource } from "./linkedCancellationSource";

interface TestEventId {
  uri: string;
  id: string;
}
type TestEventWithMessage = TestEventId & { message: string };

// All notification types that may be produce by our custom JSON test reporter
const NOTIFICATION_TYPES = {
  start: new rpc.NotificationType<TestEventId>("start"),
  pass: new rpc.NotificationType<TestEventId>("pass"),
  skip: new rpc.NotificationType<TestEventId>("skip"),
  fail: new rpc.NotificationType<TestEventWithMessage>("fail"),
  error: new rpc.NotificationType<TestEventWithMessage>("error"),
  finish: new rpc.NotificationType<void>("finish"),
};

export enum Mode {
  Run = "run",
  RunInTerminal = "runInTerminal",
  Debug = "debug",
}

// The StreamingRunner class is responsible for executing the test process or launching the debugger while handling the
// streaming events to update the test explorer status
export class StreamingRunner implements vscode.Disposable {
  private promises: Promise<void>[] = [];
  private disposables: vscode.Disposable[] = [];
  private readonly findTestItem: (
    id: string,
    uri: vscode.Uri,
  ) => Promise<vscode.TestItem | undefined>;

  private readonly tcpServer: net.Server;
  private tcpPort: string | undefined;
  private connection: rpc.MessageConnection | undefined;
  private executionPromise:
    | { resolve: () => void; reject: (error: Error) => void }
    | undefined;

  private run: vscode.TestRun | undefined;
  private terminals = new Map<string, vscode.Terminal>();
  private currentWorkspace: Workspace | undefined;

  constructor(
    context: vscode.ExtensionContext,
    findTestItem: (
      id: string,
      uri: vscode.Uri,
    ) => Promise<vscode.TestItem | undefined>,
  ) {
    this.findTestItem = findTestItem;
    this.tcpServer = this.startServer();

    context.subscriptions.push(
      vscode.window.onDidCloseTerminal((terminal) => {
        this.terminals.delete(terminal.name);
      }),
    );
  }

  async execute(
    currentRun: vscode.TestRun,
    command: string,
    env: NodeJS.ProcessEnv,
    workspace: Workspace,
    mode: Mode,
    linkedCancellationSource: LinkedCancellationSource,
  ) {
    this.currentWorkspace = workspace;
    this.run = currentRun;

    await new Promise<void>((resolve, reject) => {
      this.executionPromise = { resolve, reject };
      const abortController = new AbortController();

      linkedCancellationSource.onCancellationRequested(async () => {
        this.run!.appendOutput("\r\nTest run cancelled.");
        abortController.abort();
        await this.finalize();
      });

      if (mode === Mode.Run) {
        this.spawnTestProcess(
          command,
          env,
          workspace.workspaceFolder.uri.fsPath,
          abortController,
        );
      } else if (mode === Mode.RunInTerminal) {
        this.runInTerminal(command, env, workspace.workspaceFolder);
      } else {
        // eslint-disable-next-line @typescript-eslint/no-floating-promises
        this.launchDebugger(command, env, workspace);
      }
    });
  }

  dispose() {
    this.tcpServer.close();
    this.connection?.dispose();
  }

  // Launches the debugger with streaming updates
  private async launchDebugger(
    command: string,
    env: NodeJS.ProcessEnv,
    workspace: Workspace,
  ) {
    const successFullyStarted = await vscode.debug.startDebugging(
      workspace.workspaceFolder,
      {
        type: "ruby_lsp",
        name: "Debug",
        request: "launch",
        program: command,
        env: {
          ...env,
          DISABLE_SPRING: "1",
          RUBY_LSP_REPORTER_PORT: this.tcpPort,
        },
      },
      { testRun: this.run },
    );

    if (!successFullyStarted) {
      this.executionPromise!.reject(
        new Error("Failed to start debugging session"),
      );
    }
  }

  // Run the given test in the terminal
  private runInTerminal(
    command: string,
    env: NodeJS.ProcessEnv,
    workspaceFolder: vscode.WorkspaceFolder,
  ) {
    const cwd = workspaceFolder.uri.fsPath;
    const name = `${workspaceFolder.name}: test`;
    let terminal = vscode.window.terminals.find((t) => t.name === name);
    if (!terminal) {
      terminal = vscode.window.createTerminal({
        name,
        cwd,
        env,
      });
    }

    // Set the TCP port information every time even if there's an existing terminal. The user can close the editor
    // window or reload extensions, which will assign a new port but maintain the same terminal
    if (process.platform === "win32") {
      terminal.sendText(
        `$env:RUBY_LSP_REPORTER_PORT="${this.tcpPort}"; Clear-Host`,
      );
    } else {
      terminal.sendText(
        `export RUBY_LSP_REPORTER_PORT="${this.tcpPort}"; clear`,
      );
    }

    this.terminals.set(name, terminal);

    terminal.show();
    terminal.sendText(command);
  }

  // Spawns the test process and redirects any stdout or stderr output to the test run output
  private spawnTestProcess(
    command: string,
    env: NodeJS.ProcessEnv,
    cwd: string,
    abortController: AbortController,
  ) {
    const testProcess = spawn(command, {
      env: { ...env, RUBY_LSP_REPORTER_PORT: this.tcpPort },
      stdio: ["pipe", "pipe", "pipe"],
      shell: true,
      signal: abortController.signal,
      cwd,
    });

    testProcess.stdout.on("data", (data) => {
      this.run!.appendOutput(data.toString().replace(/\n/g, "\r\n"));
    });

    testProcess.stderr.on("data", (data) => {
      this.run!.appendOutput(data.toString().replace(/\n/g, "\r\n"));
    });
  }

  private startServer() {
    const server = net.createServer();
    server.on("error", (error) => {
      throw error;
    });
    server.unref();

    server.listen(0, "localhost", () => {
      const address = server.address();

      if (!address) {
        throw new Error("Failed setup TCP server for streaming updates");
      }
      this.tcpPort =
        typeof address === "string" ? address : address.port.toString();

      // On any new connection to the TCP server, attach the JSON RPC reader and the events we defined
      server.on("connection", (socket) => {
        this.connection = rpc.createMessageConnection(
          new rpc.StreamMessageReader(socket),
          new rpc.StreamMessageWriter(socket),
        );

        // Register and start listening for events
        this.registerStreamingEvents();
        this.connection.listen();
      });
    });

    return server;
  }

  private async finalize() {
    if (this.currentWorkspace) {
      // If the tests are being executed in a terminal, send a CTRL+C signal to stop them
      const terminal = this.terminals.get(
        `${this.currentWorkspace.workspaceFolder.name}: test`,
      );

      if (terminal) {
        terminal.sendText("\u0003");
      }
    }

    await Promise.all(this.promises);

    this.disposables.forEach((disposable) => disposable.dispose());

    this.promises = [];
    this.disposables = [];

    if (this.connection) {
      this.connection.end();
      this.connection.dispose();
    }

    this.executionPromise!.resolve();
  }

  // Registers all streaming events that we will receive from the server except for the finish event, which is
  // registered to resolve the execute promise
  private registerStreamingEvents() {
    if (!this.connection) {
      return;
    }

    const startTimestamps = new Map<string, number>();
    const withDuration = (
      id: string,
      callback: (duration?: number) => void,
    ) => {
      const startTime = startTimestamps.get(id);
      const duration = startTime ? Date.now() - startTime : undefined;
      callback(duration);
    };

    // Handle the JSON events being emitted by the tests
    this.disposables.push(
      this.connection.onNotification(
        NOTIFICATION_TYPES.finish,
        this.finalize.bind(this),
      ),
    );

    this.disposables.push(
      this.connection.onNotification(NOTIFICATION_TYPES.start, (params) => {
        this.promises.push(
          this.findTestItem(params.id, vscode.Uri.parse(params.uri)).then(
            (test) => {
              if (test) {
                this.run!.started(test);
                startTimestamps.set(test.id, Date.now());
              }
            },
          ),
        );
      }),
    );

    this.disposables.push(
      this.connection.onNotification(NOTIFICATION_TYPES.pass, (params) => {
        this.promises.push(
          this.findTestItem(params.id, vscode.Uri.parse(params.uri)).then(
            (test) => {
              if (test) {
                withDuration(test.id, (duration) =>
                  this.run!.passed(test, duration),
                );
              }
            },
          ),
        );
      }),
    );

    this.disposables.push(
      this.connection.onNotification(NOTIFICATION_TYPES.fail, (params) => {
        this.promises.push(
          this.findTestItem(params.id, vscode.Uri.parse(params.uri)).then(
            (test) => {
              if (test) {
                withDuration(test.id, (duration) =>
                  this.run!.failed(
                    test,
                    new vscode.TestMessage(params.message),
                    duration,
                  ),
                );
              }
            },
          ),
        );
      }),
    );

    this.disposables.push(
      this.connection.onNotification(NOTIFICATION_TYPES.error, (params) => {
        this.promises.push(
          this.findTestItem(params.id, vscode.Uri.parse(params.uri)).then(
            (test) => {
              if (test) {
                withDuration(test.id, (duration) =>
                  this.run!.errored(
                    test,
                    new vscode.TestMessage(params.message),
                    duration,
                  ),
                );
              }
            },
          ),
        );
      }),
    );

    this.disposables.push(
      this.connection.onNotification(NOTIFICATION_TYPES.skip, (params) => {
        this.promises.push(
          this.findTestItem(params.id, vscode.Uri.parse(params.uri)).then(
            (test) => {
              if (test) {
                this.run!.skipped(test);
              }
            },
          ),
        );
      }),
    );
  }
}
