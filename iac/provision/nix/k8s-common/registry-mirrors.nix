# Registry mirror configuration for RKE2/containerd
# Routes image pulls through Harbor proxy cache
{ config, pkgs, lib, ... }:

let
  harborAddr = config.kss.cluster.harborAddr;
in
{
  environment.etc."rancher/rke2/registries.yaml" = {
    mode = "0644";
    text = ''
      mirrors:
        docker.io:
          endpoint:
            - "https://${harborAddr}"
          rewrite:
            "^(.*)$": "docker.io/$1"
        ghcr.io:
          endpoint:
            - "https://${harborAddr}"
          rewrite:
            "^(.*)$": "ghcr.io/$1"
        quay.io:
          endpoint:
            - "https://${harborAddr}"
          rewrite:
            "^(.*)$": "quay.io/$1"
        ${harborAddr}:
          endpoint:
            - "https://${harborAddr}"

      configs:
        "${harborAddr}":
          tls:
            insecure_skip_verify: true
    '';
  };
}
