/*

# Updates

Before a major version update, make a copy of this directory. (We like to
keep the old version around for a short time after major updates.) Add a
top-level attribute to `top-level/all-packages.nix`.

1. Update the URL in `pkgs/development/libraries/qt-5/$VERSION/fetch.sh`.
2. From the top of the Nixpkgs tree, run
   `./maintainers/scripts/fetch-kde-qt.sh > pkgs/development/libraries/qt-5/$VERSION/srcs.nix`.
3. Check that the new packages build correctly.
4. Commit the changes and open a pull request.

*/

{
  newScope,
  stdenv, fetchurl, fetchpatch, fetchFromGitHub, makeSetupHook, makeWrapper,
  bison, cups ? null, harfbuzz, libGL, perl,
  gstreamer, gst-plugins-base, gtk3, dconf,
  llvmPackages_5,

  # options
  developerBuild ? false,
  decryptSslTraffic ? false,
  debug ? false,
}:

with stdenv.lib;

let

  qtCompatVersion = srcs.qtbase.version;

  stdenvActual = if stdenv.cc.isClang then llvmPackages_5.stdenv else stdenv;

  mirror = "https://download.qt.io";
  srcs = import ./srcs.nix { inherit fetchurl; inherit mirror; } // {
    # Community port of the now unmaintained upstream qtwebkit.
    qtwebkit = rec {
      src = fetchFromGitHub {
        owner = "qtwebkit";
        repo = "qtwebkit";
        rev = "qtwebkit-${version}";
        sha256 = "11lc5sk10d9cyg8jqkbgkqiap72b9rax7hy61nm90zw9749y2yfg";
      };
      version = "5.212.0-alpha4";
    };
  };

  patches = {
    qtbase =
      optionals stdenv.isDarwin [
        ./qtbase.patch.d/0001-qtbase-mkspecs-mac.patch
        ./qtbase.patch.d/0002-qtbase-mac.patch
        ./qtbase.patch.d/0013-define-kiosurfacesuccess.patch
      ]
      ++ [
        ./qtbase.patch.d/0003-qtbase-mkspecs.patch
        ./qtbase.patch.d/0004-qtbase-replace-libdir.patch
        ./qtbase.patch.d/0005-qtbase-cmake.patch
        ./qtbase.patch.d/0006-qtbase-gtk3.patch
        ./qtbase.patch.d/0007-qtbase-xcursor.patch
        ./qtbase.patch.d/0008-qtbase-xcompose.patch
        ./qtbase.patch.d/0009-qtbase-tzdir.patch
        ./qtbase.patch.d/0010-qtbase-qtpluginpath.patch
        ./qtbase.patch.d/0011-qtbase-assert.patch
        ./qtbase.patch.d/0012-fix-header_module.patch

        # Ensure -I${includedir} is added to Cflags in pkg-config files.
        # See https://github.com/NixOS/nixpkgs/issues/52457
        ./qtbase.patch.d/0014-qtbase-pkg-config.patch

        # https://bugreports.qt.io/browse/QTBUG-81715
        # remove after updating to qt > 5.12.7
        (fetchpatch {
          name = "fix-qt5_make_output_file-cmake-macro.patch";
          url = "https://code.qt.io/cgit/qt/qtbase.git/patch/?id=8a3fde00bf53d99e9e4853e8ab97b0e1bcf74915";
          sha256 = "1gpcbdpyazdxnmldvhsf3pfwr2gjvi08x3j6rxf543rq01bp6cpx";
        })
        (fetchpatch {
          name = "QTBUG-78937.patch";
          url = "https://code.qt.io/cgit/qt/qtbase.git/patch/?id=67a9c600ad14ee44501a6df3509daa8234b97606";
          sha256 = "1jiky1w9j8rka78r4q0yabb8w2l5j6csdjysynz7gs1ry4xjfdxd";
        })
      ];
    qtdeclarative = [ ./qtdeclarative.patch ];
    qtscript = [ ./qtscript.patch ];
    qtserialport = [ ./qtserialport.patch ];
    qtwebengine = [
      ./qtwebengine-no-build-skip.patch
      # https://gitlab.freedesktop.org/pulseaudio/pulseaudio/issues/707
      # https://bugreports.qt.io/browse/QTBUG-77037
      (fetchpatch {
        name = "fix-build-with-pulseaudio-13.0.patch";
        url = "https://git.archlinux.org/svntogit/packages.git/plain/trunk/qtbug-77037-workaround.patch?h=packages/qt5-webengine&id=fc77d6b3d5ec74e421b58f199efceb2593cbf951";
        sha256 = "1gv733qfdn9746nbqqxzyjx4ijjqkkb7zb71nxax49nna5bri3am";
      })
    ] ++ optionals stdenv.isDarwin [
      ./qtwebengine-darwin-no-platform-check.patch
      ./qtwebengine-darwin-fix-failed-static-assertion.patch
    ];
    qtwebkit = [
      (fetchpatch {
        name = "qtwebkit-bison-3.7-build.patch";
        url = "https://github.com/qtwebkit/qtwebkit/commit/d92b11fea65364fefa700249bd3340e0cd4c5b31.patch";
        sha256 = "0h8ymfnwgkjkwaankr3iifiscsvngqpwb91yygndx344qdiw9y0n";
      })
      ./qtwebkit.patch
    ] ++ optionals stdenv.isDarwin [
      ./qtwebkit-darwin-no-readline.patch
      ./qtwebkit-darwin-no-qos-classes.patch
    ];
    qttools = [ ./qttools.patch ];
  };

  qtModule =
    import ../qtModule.nix
    {
      inherit perl;
      inherit (stdenv) lib;
      # Use a variant of mkDerivation that does not include wrapQtApplications
      # to avoid cyclic dependencies between Qt modules.
      mkDerivation =
        import ../mkDerivation.nix
        { inherit (stdenv) lib; inherit debug; wrapQtAppsHook = null; }
        stdenvActual.mkDerivation;
    }
    { inherit self srcs patches; };

  addPackages = self: with self;
    let
      callPackage = self.newScope { inherit qtCompatVersion qtModule srcs; };
    in {

      mkDerivationWith =
        import ../mkDerivation.nix
        { inherit (stdenv) lib; inherit debug; inherit (self) wrapQtAppsHook; };

      mkDerivation = mkDerivationWith stdenvActual.mkDerivation;

      qtbase = callPackage ../modules/qtbase.nix {
        inherit (srcs.qtbase) src version;
        patches = patches.qtbase;
        inherit bison cups harfbuzz libGL;
        withGtk3 = true; inherit dconf gtk3;
        inherit developerBuild decryptSslTraffic;
      };

      qtcharts = callPackage ../modules/qtcharts.nix {};
      qtconnectivity = callPackage ../modules/qtconnectivity.nix {};
      qtdeclarative = callPackage ../modules/qtdeclarative.nix {};
      qtdoc = callPackage ../modules/qtdoc.nix {};
      qtgamepad = callPackage ../modules/qtgamepad.nix {};
      qtgraphicaleffects = callPackage ../modules/qtgraphicaleffects.nix {};
      qtimageformats = callPackage ../modules/qtimageformats.nix {};
      qtlocation = callPackage ../modules/qtlocation.nix {};
      qtmacextras = callPackage ../modules/qtmacextras.nix {};
      qtmultimedia = callPackage ../modules/qtmultimedia.nix {
        inherit gstreamer gst-plugins-base;
      };
      qtnetworkauth = callPackage ../modules/qtnetworkauth.nix {};
      qtquick1 = null;
      qtquickcontrols = callPackage ../modules/qtquickcontrols.nix {};
      qtquickcontrols2 = callPackage ../modules/qtquickcontrols2.nix {};
      qtscript = callPackage ../modules/qtscript.nix {};
      qtsensors = callPackage ../modules/qtsensors.nix {};
      qtserialbus = callPackage ../modules/qtserialbus.nix {};
      qtserialport = callPackage ../modules/qtserialport.nix {};
      qtspeech = callPackage ../modules/qtspeech.nix {};
      qtsvg = callPackage ../modules/qtsvg.nix {};
      qtscxml = callPackage ../modules/qtscxml.nix {};
      qttools = callPackage ../modules/qttools.nix {};
      qttranslations = callPackage ../modules/qttranslations.nix {};
      qtvirtualkeyboard = callPackage ../modules/qtvirtualkeyboard.nix {};
      qtwayland = callPackage ../modules/qtwayland.nix {};
      qtwebchannel = callPackage ../modules/qtwebchannel.nix {};
      qtwebengine = callPackage ../modules/qtwebengine.nix {};
      qtwebglplugin = callPackage ../modules/qtwebglplugin.nix {};
      qtwebkit = callPackage ../modules/qtwebkit.nix {};
      qtwebsockets = callPackage ../modules/qtwebsockets.nix {};
      qtwebview = callPackage ../modules/qtwebview.nix {};
      qtx11extras = callPackage ../modules/qtx11extras.nix {};
      qtxmlpatterns = callPackage ../modules/qtxmlpatterns.nix {};

      env = callPackage ../qt-env.nix {};
      full = env "qt-full-${qtbase.version}" ([
        qtcharts qtconnectivity qtdeclarative qtdoc qtgamepad qtgraphicaleffects
        qtimageformats qtlocation qtmultimedia qtquickcontrols qtquickcontrols2
        qtscript qtsensors qtserialport qtsvg qttools qttranslations
        qtvirtualkeyboard qtwebchannel qtwebengine qtwebkit qtwebsockets
        qtwebview qtx11extras qtxmlpatterns
      ] ++ optional (!stdenv.isDarwin) qtwayland
        ++ optional (stdenv.isDarwin) qtmacextras);

      qmake = makeSetupHook {
        deps = [ self.qtbase.dev ];
        substitutions = {
          fix_qmake_libtool = ../hooks/fix-qmake-libtool.sh;
        };
      } ../hooks/qmake-hook.sh;

      wrapQtAppsHook = makeSetupHook {
        deps =
          [ self.qtbase.dev makeWrapper ]
          ++ optional stdenv.isLinux self.qtwayland.dev;
      } ../hooks/wrap-qt-apps-hook.sh;
    };

   self = makeScope newScope addPackages;

in self
