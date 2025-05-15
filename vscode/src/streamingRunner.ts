import { spawn } from "child_process";
import net from "net";
import os from "os";
import path from "path";

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
  start: new rpc.NotificationType<TestEventId & { line: number }>("start"),
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
  tcpPort: string | undefined;
  private promises: Promise<void>[] = [];
  private disposables: vscode.Disposable[] = [];
  private readonly findTestItem: (
    id: string,
    uri: vscode.Uri,
    line?: number,
  ) => Promise<vscode.TestItem | undefined>;

  private readonly createTestRun: (
    request: vscode.TestRunRequest,
    name?: string,
    persist?: boolean,
  ) => vscode.TestRun;

  private tcpServer: net.Server | undefined;
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
    createTestRun: (
      request: vscode.TestRunRequest,
      name?: string,
      persist?: boolean,
    ) => vscode.TestRun,
  ) {
    this.findTestItem = findTestItem;
    this.createTestRun = createTestRun;

    context.subscriptions.push(
      vscode.window.onDidCloseTerminal((terminal) => {
        this.terminals.delete(terminal.name);
      }),
    );
  }

  async activate() {
    this.tcpServer = await this.startServer();
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
        await this.finalize(true);
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
    this.tcpServer?.close();
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
        env: { ...env, DISABLE_SPRING: "1" },
      },
      { testRun: this.run },
    );

    if (!successFullyStarted) {
      this.executionPromise!.reject(
        new Error("Failed to start debugging session"),
      );
    }

    const promise = new Promise<void>((resolve) => {
      const disposable = vscode.debug.onDidTerminateDebugSession((_session) => {
        disposable.dispose();
        resolve();
      });
    });

    this.promises.push(promise);
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
      });
    }

    // We need to send RUBYOPT since that hooks up the custom LSP test reporters and the user's shell may override it
    if (process.platform === "win32") {
      terminal.sendText(`$env:RUBYOPT="${env.RUBYOPT}"; Clear-Host`);
    } else {
      terminal.sendText(`export RUBYOPT="${env.RUBYOPT}"; clear`);
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
    const promise = new Promise<void>((resolve, _reject) => {
      const testProcess = spawn(command, {
        env,
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

      testProcess.on("exit", (_code) => {
        resolve();
      });
    });

    this.promises.push(promise);
  }

  private async startServer(): Promise<net.Server> {
    // Listening on the TCP connection is asynchronous. We can only resolve the promise once we know what port has been
    // assigned, otherwise we risk trying to start tests without a port
    return new Promise((resolve, reject) => {
      const server = net.createServer();
      server.on("error", reject);
      server.unref();

      server.listen(0, "localhost", async () => {
        const address = server.address();

        if (!address) {
          throw new Error("Failed setup TCP server for streaming updates");
        }
        this.tcpPort =
          typeof address === "string" ? address : address.port.toString();

        const tempDirUri = vscode.Uri.file(path.join(os.tmpdir(), "ruby-lsp"));

        await vscode.workspace.fs.createDirectory(tempDirUri);
        await vscode.workspace.fs.writeFile(
          vscode.Uri.joinPath(tempDirUri, "test_reporter_port"),
          Buffer.from(this.tcpPort!.toString()),
        );

        // On any new connection to the TCP server, attach the JSON RPC reader and the events we defined
        server.on("connection", (socket) => {
          this.connection = rpc.createMessageConnection(
            new rpc.StreamMessageReader(socket),
            new rpc.StreamMessageWriter(socket),
          );

          // Register and start listening for events
          this.registerStreamingEvents();

          if (!this.run) {
            this.run = this.createTestRun(
              new vscode.TestRunRequest(),
              "on_demand_run_in_terminal",
            );
          }

          this.connection.listen();
        });

        resolve(server);
      });
    });
  }

  private async finalize(cancellation: boolean) {
    if (cancellation && this.currentWorkspace) {
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

    if (this.run && this.run.name === "on_demand_run_in_terminal") {
      this.run.end();
    }

    this.run = undefined;
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
      this.connection.onNotification(NOTIFICATION_TYPES.finish, () =>
        this.finalize(false),
      ),
    );

    this.disposables.push(
      this.connection.onNotification(NOTIFICATION_TYPES.start, (params) => {
        this.promises.push(
          this.findTestItem(
            params.id,
            vscode.Uri.parse(params.uri),
            params.line,
          ).then((test) => {
            if (test) {
              this.run!.started(test);
              startTimestamps.set(test.id, Date.now());
            }
          }),
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
