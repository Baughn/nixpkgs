# verifies:
#   1. nginx generates config file with shared http context definitions above
#      generated virtual hosts config.
#
#   2. nginx runs with a config file that contains non-ascii letters.

import ./make-test.nix ({ pkgs, ...} : {
  name = "nginx";
  meta = with pkgs.stdenv.lib.maintainers; {
    maintainers = [ mbbx6spp ];
  };

  nodes = {
    webserver =
      { config, pkgs, ... }:
      { services.nginx.enable = true;
        services.nginx.commonHttpConfig = ''
        log_format ceeformat '@cee: {"status":"$status",'
          '"request_time":$request_time,'
          '"upstream_response_time":$upstream_response_time,'
          '"pipe":"$pipe","bytes_sent":$bytes_sent,'
          '"connection":"$connection",'
          '"remote_addr":"$remote_addr",'
          '"host":"$host",'
          '"timestamp":"$time_iso8601",'
          '"request":"$request",'
          '"http_referer":"$http_referer",'
          '"upstream_addr":"$upstream_addr"}';
        '';
        services.nginx.virtualHosts."0.my.test" = {
          extraConfig = ''
            access_log syslog:server=unix:/dev/log,facility=user,tag=mytag,severity=info ceeformat;
            # This comment is lifted from bug #22883:
            # Statusseite für Monitoring freigeben
          '';
        };
      };
  };

  testScript = ''
    startAll;

    $webserver->waitForUnit("nginx");
    $webserver->waitForOpenPort("80");
  '';
})
