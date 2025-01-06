import path from "path";

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
