import * as vscode from "vscode";

import { Command } from "./common";
import { Workspace } from "./workspace";

const CHAT_AGENT_ID = "rubyLsp.chatAgent";
const DESIGN_PROMPT = `
  You are a domain driven design and Ruby on Rails expert.
  The user will provide you with details about their Rails application.
  The user will ask you to help model a single specific concept.

  Analyze the provided concept carefully and think step by step. Consider the following aspects:
  1. The core purpose of the concept
  2. Its relationships with other potential entities in the system
  3. The attributes that would best represent this concept in a database

  Based on your analysis, suggest an appropriate model name and attributes to effectively model the concept.
  Follow these guidelines:

  1. Choose a clear, singular noun for the model name that accurately represents the concept
  2. Select attributes that capture the essential characteristics of the concept
  3. Use appropriate data types for each attribute (e.g. string, integer, datetime, boolean)
  4. Consider adding foreign keys for relationships with other models, if applicable

  After determining the model structure, generate the Rails commands to create the model and any associated resources.
  Include all relevant \`generate\` commands in a single Markdown shell code block at the end of your response.

  The \`generate\` commands should ONLY include the type of generator and arguments, not the \`rails generate\` part
  (e.g.: \`model User name:string\` but not \`rails generate model User name:string\`).
  NEVER include commands to migrate the database as part of the code block.
  NEVER include redundant commands (e.g. including the migration and model generation commands for the same model).
`.trim();

export class ChatAgent implements vscode.Disposable {
  private readonly agent: vscode.ChatParticipant;
  private readonly showWorkspacePick: () => Promise<Workspace | undefined>;

  constructor(context: vscode.ExtensionContext, showWorkspacePick: () => Promise<Workspace | undefined>) {
    this.agent = vscode.chat.createChatParticipant(CHAT_AGENT_ID, this.handler.bind(this));
    this.agent.iconPath = vscode.Uri.joinPath(context.extensionUri, "icon.png");
    this.showWorkspacePick = showWorkspacePick;
  }

  dispose() {
    this.agent.dispose();
  }

  // Handle a new chat message or command
  private async handler(
    request: vscode.ChatRequest,
    context: vscode.ChatContext,
    stream: vscode.ChatResponseStream,
    token: vscode.CancellationToken,
  ) {
    if (this.withinConversation("design", request, context)) {
      return this.runDesignCommand(request, context, stream, token);
    }

    stream.markdown("Please indicate which command you would like to use for our chat.");
    return { metadata: { command: "" } };
  }

  // Logic for the domain driven design command
  private async runDesignCommand(
    request: vscode.ChatRequest,
    context: vscode.ChatContext,
    stream: vscode.ChatResponseStream,
    token: vscode.CancellationToken,
  ) {
    const previousInteractions = this.previousInteractions(context);
    const messages = [
      vscode.LanguageModelChatMessage.User(`User prompt: ${request.prompt}`),
      vscode.LanguageModelChatMessage.User(DESIGN_PROMPT),
      vscode.LanguageModelChatMessage.User(`Previous interactions with the user: ${previousInteractions}`),
    ];
    const workspace = await this.showWorkspacePick();

    // On the first interaction with the design command, we gather the application's schema and include it as part of
    // the prompt
    if (request.command && workspace) {
      const schema = await this.schema(workspace);

      if (schema) {
        messages.push(vscode.LanguageModelChatMessage.User(`Existing application schema: ${schema}`));
      }
    }

    try {
      // Select the LLM model
      const [model] = await vscode.lm.selectChatModels({
        vendor: "copilot",
        family: "gpt-4o",
      });

      stream.progress("Designing the models for the requested concept...");
      const chatResponse = await model.sendRequest(messages, {}, token);

      let response = "";
      for await (const fragment of chatResponse.text) {
        // Maybe show the buttons here and display multiple shell blocks?
        stream.markdown(fragment);
        response += fragment;
      }

      const match = /(?<=```shell)[^.$]*(?=```)/.exec(response);

      if (workspace && match && match[0]) {
        // The shell code block includes all of the `rails generate` commands. We need to strip out the `rails generate`
        // from all of them since our commands only accept from the generator forward
        const commandList = match[0]
          .trim()
          .split("\n")
          .map((command) => {
            return command.replace(/\s*(bin\/rails|rails) generate\s*/, "");
          });

        stream.button({
          command: Command.RailsGenerate,
          title: "Generate with Rails",
          arguments: [commandList, workspace],
        });

        stream.button({
          command: Command.RailsDestroy,
          title: "Revert previous generation",
          arguments: [commandList, workspace],
        });
      }
    } catch (err) {
      this.handleError(err, stream);
    }

    return { metadata: { command: "design" } };
  }

  private async schema(workspace: Workspace) {
    try {
      const content = await vscode.workspace.fs.readFile(
        vscode.Uri.joinPath(workspace.workspaceFolder.uri, "db/schema.rb"),
      );
      return content.toString();
    } catch (_error) {
      // db/schema.rb doesn't exist
    }

    try {
      const content = await vscode.workspace.fs.readFile(
        vscode.Uri.joinPath(workspace.workspaceFolder.uri, "db/structure.sql"),
      );
      return content.toString();
    } catch (_error) {
      // db/structure.sql doesn't exist
    }

    return undefined;
  }

  // Returns `true` if the current or any previous interactions with the chat match the given `command`. Useful for
  // ensuring that the user can continue chatting without having to re-type the desired command multiple times
  private withinConversation(command: string, request: vscode.ChatRequest, context: vscode.ChatContext) {
    return (
      request.command === command ||
      (!request.command &&
        context.history.some((entry) => entry instanceof vscode.ChatRequestTurn && entry.command === command))
    );
  }

  // Default error handling
  private handleError(err: any, stream: vscode.ChatResponseStream) {
    if (err instanceof vscode.LanguageModelError) {
      if (err.cause instanceof Error && err.cause.message.includes("off_topic")) {
        stream.markdown("Sorry, I can only help you with Ruby related questions");
      }
    } else {
      throw err;
    }
  }

  // Get the content of all previous interactions (including requests and responses) as a string
  private previousInteractions(context: vscode.ChatContext): string {
    let history = "";

    context.history.forEach((entry) => {
      if (entry instanceof vscode.ChatResponseTurn) {
        if (entry.participant === CHAT_AGENT_ID) {
          let content = "";

          entry.response.forEach((part) => {
            if (part instanceof vscode.ChatResponseMarkdownPart) {
              content += part.value.value;
            }
          });

          history += `Response: ${content}`;
        }
      } else {
        history += `Request: ${entry.prompt}`;
      }
    });

    return history;
  }
}
