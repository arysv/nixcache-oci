{
  description = "User configuration — add your packages and NixOS hosts here";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    obk-src = {
      url = "git+https://github.com/OpenBangla/OpenBangla-Keyboard.git?submodules=1&shallow=1";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, obk-src }:
  let
    systems = [ "x86_64-linux" "aarch64-linux" ];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    
    buildObk = pkgs:
      let
        riti = pkgs.rustPlatform.buildRustPackage {
          pname = "riti";
          version = "2.0.0-unstable";
          src = obk-src + "/src/engine/riti";
          cargoLock.lockFile = ./Cargo.lock;
          postPatch = ''
            cp ${./Cargo.lock} Cargo.lock
          '';
          doCheck = false;

          installPhase = ''
            mkdir -p $out/lib $out/include
            find target -name "*.a" -exec cp {} $out/lib/ \;
            cp include/riti.h $out/include/
          '';
        };
      in
      pkgs.stdenv.mkDerivation {
        pname = "openbangla-keyboard";
        version = "2.0.0-unstable";

        src = obk-src;

        nativeBuildInputs = with pkgs; [
          cmake pkg-config qt5.qttools qt5.wrapQtAppsHook rustc cargo
        ];
        buildInputs = with pkgs; [ qt5.qtbase ibus zstd riti ];

        preConfigure = ''
          substituteInPlace CMakeLists.txt \
            --replace-fail 'set(CMAKE_INSTALL_PREFIX "/usr")' ""

          cat > src/engine/riti/CMakeLists.txt << CMAKE_EOF
          add_library(riti STATIC IMPORTED GLOBAL)
          set_target_properties(riti PROPERTIES
            IMPORTED_LOCATION "${riti}/lib/libriti.a"
            INTERFACE_INCLUDE_DIRECTORIES "${riti}/include"
          )
          target_include_directories(riti INTERFACE "${riti}/include")
          CMAKE_EOF
        '';

        cmakeFlags = [ "-DCMAKE_BUILD_TYPE=Release" ];

        postFixup = ''
          wrapQtApp "$out/share/openbangla-keyboard/ibus-openbangla" 2>/dev/null || true
          wrapQtApp "$out/share/openbangla-keyboard/openbangla-gui" 2>/dev/null || true

          mkdir -p $out/bin
          ln -s $out/share/openbangla-keyboard/openbangla-gui $out/bin/openbangla-gui
        '';

        meta = with pkgs.lib; {
          description = "Open Source Bangla Input Method for Linux";
          homepage = "https://github.com/OpenBangla/OpenBangla-Keyboard";
          license = licenses.gpl3Only;
          platforms = platforms.linux;
          mainProgram = "openbangla-gui";
        };
      };

  in {
    packages = forAllSystems (system:
    let pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.hello;
      htop = pkgs.htop;
      tree = pkgs.tree;

      # Custom package that won't be on cache.nixos.org
      nixcache-test = pkgs.writeShellScriptBin "nixcache-test" ''
        echo "Hello from nixcache-oci! Cache is working."
        echo "Built at: 2026-04-05"
      '';

      # OpenBangla Keyboard
      openbangla-keyboard = buildObk pkgs;
    });

    devShells = forAllSystems (system:
    let pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.mkShell {
        name = "openbangla-keyboard-dev";
        nativeBuildInputs = with pkgs; [
          cmake pkg-config qt5.qttools rustc cargo rustPlatform.bindgenHook
        ];
        buildInputs = with pkgs; [ qt5.qtbase ibus zstd ];
      };
    });

    nixosModules.openbangla-keyboard = { config, lib, pkgs, ... }:
      with lib;
      let
        cfg = config.programs.openbangla-keyboard;
        pkg = self.packages.${pkgs.system}.openbangla-keyboard;
      in
      {
        options.programs.openbangla-keyboard = {
          enable = mkEnableOption "OpenBangla Keyboard, a Bangla input method";
        };

        config = mkIf cfg.enable {
          environment.systemPackages = [ pkg ];
          i18n.inputMethod = {
            enabled = mkDefault "ibus";
            ibus.engines = mkIf (config.i18n.inputMethod.enabled == "ibus") [ pkg ];
          };
        };
      };

    homeManagerModules.openbangla-keyboard = { config, lib, pkgs, ... }:
      with lib;
      let
        cfg = config.programs.openbangla-keyboard;
        pkg = self.packages.${pkgs.system}.openbangla-keyboard;
      in
      {
        options.programs.openbangla-keyboard = {
          enable = mkEnableOption "OpenBangla Keyboard, a Bangla input method";
        };

        config = mkIf cfg.enable {
          home.packages = [ pkg ];
        };
      };

    # nixosConfigurations.my-host = nixpkgs.lib.nixosSystem { ... };
  };
}

