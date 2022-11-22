{ pkgs, lib, config, ... }:

let
  cfg = config.timescale;
  types = lib.types;


  setupScript = pkgs.writeShellScriptBin "setup-timescale" ''
    set -euo pipefail
    export PATH=${postgresPackageSet.${cfg.version}}/bin:${pkgs.coreutils}/bin
    # Abort if the data dir already exists
    [[ ! -d "$PGDATA" ]] || exit 0
    initdb ${lib.concatStringsSep " " cfg.initdbArgs}
    cat >> "$PGDATA/postgresql.conf" <<EOF
    listen_addresses = '''
    unix_socket_directories = '$PGDATA'
    EOF
    ## ${pkgs.timescaledb-tune}/bin/timescaledb-tune -yes
    ## echo "CREATE DATABASE ${cfg.databaseName};" | postgres --single -E postgres
  '';
  # TODO: Add TSDB Extensions

  startScript = pkgs.writeShellScriptBin "start-timescale" ''
    set -euo pipefail
    ${setupScript}/bin/setup-timescale
    exec ${postgresPackageSet.${cfg.version}}/bin/postgres
  '';

  postgresPackageSet = {
    "11" = pkgs.postgresql_11;
    "12" = pkgs.postgresql_12;
    "13" = pkgs.postgresql_13;
    "14" = pkgs.postgresql_14;
  };

  timescaledbPackageSet = {
    "11" = pkgs.postgresql11Packages.timescaledb;
    "12" = pkgs.postgresql12Packages.timescaledb;
    "13" = pkgs.postgresql13Packages.timescaledb;
    "14" = pkgs.postgresql14Packages.timescaledb;
  };

in
{
  options.timescale = {
    enable = lib.mkEnableOption ''
      Add postgreSQL process and psql-devenv script.
    '';

    version = lib.mkOption {
      type = types.enum [ "11" "12" "13" "14" ];
      default = "14";
      description = "Which version of postgreSQL to use";
    };

    databaseName = lib.mkOption {
      type = types.string;
      default = "tsdb";
      description = ''
        Name of the database to be created on startup and configured for Timescale.
      '';
    };


    initdbArgs = lib.mkOption {
      type = types.listOf types.lines;
      default = [ "--no-locale" ];
      example = [ "--data-checksums" "--allow-group-access" ];
      description = ''
        Additional arguments passed to `initdb` during data dir
        initialisation.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    packages = [
      postgresPackageSet.${cfg.version}
      timescaledbPackageSet.${cfg.version}
      pkgs.timescaledb-tune
    ];

    env.PGDATA = config.env.DEVENV_STATE + "/timescale";

    scripts."timescale-devenv".exec = "${postgresPackageSet.${cfg.version}}/bin/psql -h $PGDATA $@";

    processes.timescale.exec = "${startScript}/bin/start-timescale";
  };
}
