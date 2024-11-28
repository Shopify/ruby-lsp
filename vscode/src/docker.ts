import path from "path";

import * as vscode from "vscode";

import { PathConverterInterface } from "./common";
import { WorkspaceChannel } from "./workspaceChannel";

export interface ComposeConfig {
  services: Record<string, ComposeService>;
  ["x-mutagen"]?: { sync: Record<string, MutagenShare> } | undefined;
}

interface ComposeService {
  volumes: ComposeVolume[];
}

interface ComposeVolume {
  type: string;
  source: string;
  target: string;
}

interface MutagenShare {
  alpha: string;
  beta: string;
}

interface MutagenMount {
  volume: string;
  source: string;
  target: string;
}

type MutagenMountMapping = Record<
  string,
  {
    source: string;
    target: string;
  }
>;

export function fetchPathMapping(
  config: ComposeConfig,
  service: string,
): Record<string, string> {
  const mutagenMounts = fetchMutagenMounts(config["x-mutagen"]?.sync || {});

  const bindings = fetchComposeBindings(
    config.services[service]?.volumes || [],
    mutagenMounts,
  );

  return bindings;
}

export class ContainerPathConverter implements PathConverterInterface {
  readonly pathMapping: [string, string][];
  private readonly outputChannel: WorkspaceChannel;

  constructor(
    pathMapping: Record<string, string>,
    outputChannel: WorkspaceChannel,
  ) {
    this.pathMapping = Object.entries(pathMapping);
    this.outputChannel = outputChannel;
  }

  toRemotePath(path: string) {
    for (const [local, remote] of this.pathMapping) {
      if (path.startsWith(local)) {
        const remotePath = path.replace(local, remote);

        this.outputChannel.debug(
          `Converted toRemotePath ${path} to ${remotePath}`,
        );

        return path.replace(local, remote);
      }
    }

    return path;
  }

  toLocalPath(path: string) {
    for (const [local, remote] of this.pathMapping) {
      if (path.startsWith(remote)) {
        const localPath = path.replace(remote, local);

        this.outputChannel.debug(
          `Converted toLocalPath ${path} to ${localPath}`,
        );

        return localPath;
      }
    }

    return path;
  }

  toRemoteUri(localUri: vscode.Uri) {
    const remotePath = this.toRemotePath(localUri.fsPath);
    return vscode.Uri.file(remotePath);
  }

  alternativePaths(path: string) {
    const alternatives = [
      this.toRemotePath(path),
      this.toLocalPath(path),
      path,
    ];

    return Array.from(new Set(alternatives));
  }
}

function fetchComposeBindings(
  volumes: ComposeVolume[],
  mutagenMounts: MutagenMountMapping,
): Record<string, string> {
  return volumes.reduce(
    (acc: Record<string, string>, volume: ComposeVolume) => {
      if (volume.type === "bind") {
        acc[volume.source] = volume.target;
      } else if (volume.type === "volume") {
        Object.entries(mutagenMounts).forEach(
          ([
            mutagenVolume,
            { source: mutagenSource, target: mutagenTarget },
          ]) => {
            if (mutagenVolume.startsWith(`volume://${volume.source}/`)) {
              const remotePath = path.resolve(volume.target, mutagenSource);
              acc[mutagenTarget] = remotePath;
            }
          },
        );
      }

      return acc;
    },
    {},
  );
}

function transformMutagenMount(alpha: string, beta: string): MutagenMount {
  const [, ...path] = alpha.replace("volume://", "").split("/");
  const [volume, source] =
    path.length > 0 ? [alpha, `./${path.join("/")}`] : [`${alpha}/`, "."];

  return { volume, source, target: beta };
}

function fetchMutagenMounts(
  sync: Record<string, MutagenShare> = {},
): MutagenMountMapping {
  return Object.entries(sync).reduce(
    (
      acc: Record<string, { source: string; target: string }>,
      [name, { alpha, beta }]: [string, MutagenShare],
    ) => {
      if (name === "defaults") return acc;

      let mount: MutagenMount | null = null;

      if (alpha.startsWith("volume://")) {
        mount = transformMutagenMount(alpha, beta);
      } else if (beta.startsWith("volume://")) {
        mount = transformMutagenMount(beta, alpha);
      }

      if (mount) {
        acc[mount.volume] = {
          source: mount.source,
          target: mount.target,
        };
      }

      return acc;
    },
    {},
  );
}
