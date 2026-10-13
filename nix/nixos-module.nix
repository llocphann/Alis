{ config, lib, pkgs, ... }:

let
  common = import ./module-common.nix { inherit lib pkgs; };
  cfg = config.programs.alis;
  wantedUnit = common.compositorUnit cfg.service.compositor;
in
{
  imports = [ common.optionsModule ];

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    systemd.user.services.alis = lib.mkIf cfg.service.enable {
      description = "Alis shell";
      wantedBy = lib.optional (wantedUnit != null) wantedUnit;
      partOf = [ "graphical-session.target" ];
      wants = [ "graphical-session-pre.target" ];
      after = [ "graphical-session-pre.target" ];
      before = [ "graphical-session.target" ];
      path = [ cfg.package ] ++ cfg.extraPackages;
      environment = common.serviceEnvironment cfg;
      unitConfig = {
        StartLimitIntervalSec = 30;
        StartLimitBurst = 3;
      };
      serviceConfig = {
        Type = "dbus";
        BusName = "org.kde.StatusNotifierWatcher";
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
    };
  };
}
