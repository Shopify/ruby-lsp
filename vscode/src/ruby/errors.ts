// Custom error types for Ruby version manager operations

/**
 * Base class for all Ruby version manager errors.
 * Provides structured error information including the version manager name and error code.
 */
export abstract class RubyVersionManagerError extends Error {
  public readonly versionManager: string;
  public readonly errorCode: string;

  constructor(message: string, versionManager: string, errorCode: string) {
    super(message);
    this.name = this.constructor.name;
    this.versionManager = versionManager;
    this.errorCode = errorCode;

    // Maintains proper stack trace for where our error was thrown (only available on V8)
    if (Error.captureStackTrace) {
      Error.captureStackTrace(this, this.constructor);
    }
  }
}

/**
 * Thrown when a version manager executable cannot be found at expected locations.
 */
export class ExecutableNotFoundError extends RubyVersionManagerError {
  public readonly searchedPaths: string[];
  public readonly configuredPath?: string;

  constructor(versionManager: string, searchedPaths: string[], configuredPath?: string) {
    const message = configuredPath
      ? `${versionManager} executable configured as ${configuredPath}, but that file doesn't exist`
      : `Cannot find ${versionManager} installation. Searched in ${searchedPaths.join(", ")}`;
    super(message, versionManager, "EXECUTABLE_NOT_FOUND");
    this.searchedPaths = searchedPaths;
    this.configuredPath = configuredPath;
  }
}

/**
 * Thrown when required configuration is missing for a version manager.
 */
export class MissingConfigurationError extends RubyVersionManagerError {
  public readonly configKey: string;

  constructor(versionManager: string, configKey: string) {
    super(
      `The ${configKey} configuration must be set when '${versionManager}' is selected as the version manager. See the [README](https://shopify.github.io/ruby-lsp/version-managers.html) for instructions.`,
      versionManager,
      "MISSING_CONFIGURATION",
    );
    this.configKey = configKey;
  }
}

/**
 * Thrown when a Ruby installation cannot be found for the requested version.
 */
export class RubyInstallationNotFoundError extends RubyVersionManagerError {
  public readonly requestedVersion?: string;
  public readonly searchedPaths?: string[];

  constructor(versionManager: string, requestedVersion?: string, searchedPaths?: string[]) {
    let message: string;
    if (searchedPaths && searchedPaths.length > 0) {
      message = requestedVersion
        ? `Cannot find Ruby installation for version ${requestedVersion}. Searched in ${searchedPaths.join(", ")}`
        : `Cannot find any Ruby installations. Searched in ${searchedPaths.join(", ")}`;
    } else {
      message = requestedVersion
        ? `Cannot find Ruby installation for version ${requestedVersion}`
        : "Cannot find any Ruby installations";
    }
    super(message, versionManager, "RUBY_NOT_FOUND");
    this.requestedVersion = requestedVersion;
    this.searchedPaths = searchedPaths;
  }
}

/**
 * Thrown when a version manager's required directory structure is not found.
 */
export class VersionManagerDirectoryNotFoundError extends RubyVersionManagerError {
  public readonly directoryName: string;

  constructor(versionManager: string, directoryName: string) {
    super(
      `The Ruby LSP version manager is configured to be ${versionManager}, but no ${directoryName} directory was found in the workspace`,
      versionManager,
      "MANAGER_DIR_NOT_FOUND",
    );
    this.directoryName = directoryName;
  }
}

/**
 * Thrown when a .ruby-version file is empty or contains invalid format.
 */
export class RubyVersionFileError extends RubyVersionManagerError {
  public readonly filePath: string;
  public readonly issue: "empty" | "invalid_format";
  public readonly content?: string;

  constructor(filePath: string, issue: "empty" | "invalid_format", content?: string) {
    const message =
      issue === "empty"
        ? `Ruby version file ${filePath} is empty`
        : `Ruby version file ${filePath} contains invalid format. Expected (engine-)?version, got ${content}`;
    super(message, "chruby", "VERSION_FILE_ERROR");
    this.filePath = filePath;
    this.issue = issue;
    this.content = content;
  }
}

/**
 * Base class for errors that occur during Ruby environment activation.
 */
export class ActivationError extends RubyVersionManagerError {
  public readonly cause?: Error;

  constructor(message: string, versionManager: string, cause?: Error) {
    super(message, versionManager, "ACTIVATION_ERROR");
    this.cause = cause;
  }
}

/**
 * Thrown when attempting to activate Ruby in an untrusted workspace (e.g., for Shadowenv).
 */
export class UntrustedWorkspaceError extends ActivationError {
  constructor(versionManager: string = "shadowenv") {
    super("Cannot activate Ruby environment in an untrusted workspace", versionManager);
  }
}

/**
 * Thrown when user cancels a Ruby activation fallback operation.
 */
export class ActivationCancellationError extends ActivationError {
  constructor(versionManager: string) {
    super("Ruby activation was cancelled by user", versionManager);
  }
}

/**
 * Thrown when no .ruby-version file can be found in the workspace hierarchy.
 */
export class RubyVersionFileNotFoundError extends RubyVersionManagerError {
  public readonly searchedPath: string;

  constructor(versionManager: string, searchedPath: string) {
    super(
      `Cannot find .ruby-version file. Please specify the Ruby version in a .ruby-version either in ${searchedPath} or in a parent directory`,
      versionManager,
      "VERSION_FILE_NOT_FOUND",
    );
    this.searchedPath = searchedPath;
  }
}
