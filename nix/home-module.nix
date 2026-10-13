{ config, lib, pkgs, ... }:

let
  common = import ./module-common.nix { inherit lib pkgs; };
  cfg = config.programs.alis;
  wantedUnit = common.compositorUnit cfg.service.compositor;
  env = common.serviceEnvironment cfg // lib.optionalAttrs (cfg.extraPackages != [ ]) {
    PATH = lib.makeBinPath ([ cfg.package ] ++ cfg.extraPackages);
  };
in
{
  imports = [ common.optionsModule ];

  options.programs.alis.configSymlink = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Expose the packaged shell at ~/.config/quickshell/alis for tools that expect the traditional path.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    xdg.configFile = lib.mkIf cfg.configSymlink.enable {
      "quickshell/alis".source = "${cfg.package}/share/quickshell/alis";
    };

    systemd.user.services.alis = lib.mkIf cfg.service.enable {
      Unit = {
        Description = "Alis shell";
        PartOf = [ "graphical-session.target" ];
        Wants = [ "graphical-session-pre.target" ];
        After = [ "graphical-session-pre.target" ];
        Before = [ "graphical-session.target" ];
        StartLimitIntervalSec = 30;
        StartLimitBurst = 3;
      };

      Service = {
        Type = "dbus";
        BusName = "org.kde.StatusNotifierWatcher";
        Environment = lib.mapAttrsToList (name: value: "${name}=${value}") env;
        ExecStart = "${lib.getExe cfg.package} run --session";
        ExecStopPost = "-${lib.getExe cfg.package} cleanup-orphans";
        SuccessExitStatus = 143;
        KillMode = "process";
        KillSignal = "SIGTERM";
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStopSec = 15;
        LimitCORE = 0;
        IOSchedulingPriority = 2;
      };

      Install.WantedBy = lib.optional (wantedUnit != null) wantedUnit;
    };
  };
}
