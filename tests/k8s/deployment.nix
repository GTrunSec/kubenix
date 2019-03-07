{ config, lib, pkgs, kubenix, images, ... }:

with lib;

let
  cfg = config.kubernetes.api.deployments.nginx;
  image = images.nginx;
in {
  imports = [ kubenix.modules.test kubenix.modules.k8s ];

  test = {
    name = "k8s-deployment";
    description = "Simple k8s testing a simple deployment";
    assertions = [{
      message = "should have correct apiVersion and kind set for 1.8+";
      assertion =
        if ((builtins.compareVersions config.kubernetes.version "1.7") <= 0)
        then cfg.apiVersion == "apps/v1beta1"
        else if ((builtins.compareVersions config.kubernetes.version "1.8") <= 0)
        then cfg.apiVersion == "apps/v1beta2"
        else cfg.apiVersion == "apps/v1";
    } {
      message = "should have corrent kind set";
      assertion = cfg.kind == "Deployment";
    } {
      message = "should have replicas set";
      assertion = cfg.spec.replicas == 10;
    }];
    testScript = ''
      $kube->waitUntilSucceeds("docker load < ${image}");
      $kube->waitUntilSucceeds("kubectl apply -f ${toYAML config.kubernetes.generated}");

      $kube->succeed("kubectl get deployment | grep -i nginx");
      $kube->waitUntilSucceeds("kubectl get deployment -o go-template nginx --template={{.status.readyReplicas}} | grep 10");
      $kube->waitUntilSucceeds("${pkgs.curl}/bin/curl http://nginx.default.svc.cluster.local | grep -i hello");
    '';
  };

  kubernetes.api.deployments.nginx = {
    spec = {
      replicas = 10;
      selector.matchLabels.app = "nginx";
      template.metadata.labels.app = "nginx";
      template.spec = {
        containers.nginx = {
          image = "${image.imageName}:${image.imageTag}";
          imagePullPolicy = "Never";
        };
      };
    };
  };

  kubernetes.api.services.nginx = {
    spec = {
      ports = [{
        name = "http";
        port = 80;
      }];
      selector.app = "nginx";
    };
  };
}