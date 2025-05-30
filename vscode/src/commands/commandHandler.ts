import * as vscode from "vscode";

/**
 * Interface for command handlers that can be registered with VS Code
 */
export interface CommandHandler {
  /**
   * The command identifier that this handler responds to
   */
  readonly commandId: string;

  /**
   * Execute the command
   */
  execute(...args: any[]): Promise<void> | void;

  /**
   * Register this command handler with VS Code
   */
  register(): vscode.Disposable;
}

/**
 * Abstract base class for command handlers with common functionality
 */
export abstract class BaseCommandHandler implements CommandHandler {
  abstract readonly commandId: string;

  abstract execute(...args: any[]): Promise<void> | void;

  /**
   * Register this command handler with VS Code
   */
  register(): vscode.Disposable {
    return vscode.commands.registerCommand(this.commandId, (...args) =>
      this.execute(...args),
    );
  }

  /**
   * Helper method to show error messages consistently
   */
  protected showError(message: string, error?: Error): void {
    const fullMessage = error ? `${message}: ${error.message}` : message;
    vscode.window.showErrorMessage(fullMessage);
  }

  /**
   * Helper method to get the active editor with validation
   */
  protected getActiveEditor(): vscode.TextEditor | undefined {
    const editor = vscode.window.activeTextEditor;
    if (!editor) {
      vscode.window.showWarningMessage("No active editor found");
      return undefined;
    }
    return editor;
  }
}
