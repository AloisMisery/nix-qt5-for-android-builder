{
  pkgs,
  lib,
}:

let

  # ===========================================================================

  qt-version-micro = "0";
  qt-version = "5.15.${qt-version-micro}";

  # https://qt.mirror.constant.com/archive/qt/5.15/5.15.0/single/qt-everywhere-src-5.15.0.tar.xz
  qt-src-archive-full = let
    # src_url_host = "download.qt.io";
    # src_url_host = "qt-mirror.dannhauer.de";
    qt-src-url-host = "qt.mirror.constant.com";
  in pkgs.fetchzip {
    url = "https://${qt-src-url-host}/archive/qt/5.15/5.15.0/single/qt-everywhere-src-${qt-version}.tar.xz";
    hash = "sha256-GR8egTgHmciurgTRkBnAZ7P1KSeG9BItX0fmz/rBmPM=";
  };

  makeRemotePatchesWithPrefix = prefix: elems: let
    xs = map (x: (x // { stripLen = 1; extraPrefix = "${prefix}/"; })) elems;
  in map pkgs.fetchpatch xs;

  qt-src-qtbase-patches = (makeRemotePatchesWithPrefix "qtbase" [
    {
      url = "https://github.com/conan-io/conan-center-index/raw/1b24f7c74/recipes/qt/5.x.x/patches/android-backtrace.diff";
      hash = "sha256-/el09OJR/e0NUfGTxEtsx1Gk/JfdzNhC7VsfBVfp+BU=";
    }
    {
      url = "https://github.com/conan-io/conan-center-index/raw/1b24f7c74/recipes/qt/5.x.x/patches/android-new-ndk.diff";
      hash = "sha256-EwJoRjF6SFDVsDxztiJMqqj/KoaNs/WIhVQqKBgBqMY=";
    }
  ]) ++ [
    ./patch-qt-5.15.0-qtbase-limits.diff
  ];

  qt-src = pkgs.applyPatches {
    name = "${qt-src-archive-full.name}-patched";
    src = qt-src-archive-full;
    patches = qt-src-qtbase-patches;
  };

  # ===========================================================================

  androidPackagesVersions = {
    cmdLineTools = "13.0";
    platformTools = "35.0.1";
    buildTools = "23.0.0";
    platform = "23";
    ndk = "25.1.8937393";
    cmake = "3.22.1";
  };

  androidComposition = pkgs.androidenv.composeAndroidPackages (with androidPackagesVersions; {
    cmdLineToolsVersion = cmdLineTools;
    platformToolsVersion = platformTools;
    buildToolsVersions = [ buildTools ];
    platformVersions = [ platform ];
    # includeSources = true;
    abiVersions = [ "x86_64" ];
    includeNDK = true;
    ndkVersion = ndk;
    cmakeVersions = [ cmake ];
  });

  androidsdk = androidComposition.androidsdk;

  androidEnvVars = rec {
    ANDROID_HOME = "${androidsdk}/libexec/android-sdk";
    ANDROID_SDK_ROOT = "${ANDROID_HOME}";

    ANDROID_NDK_ROOT = "${ANDROID_HOME}/ndk-bundle";
    ANDROID_NDK_HOME = "${ANDROID_NDK_ROOT}";

    ANDROID_PLATFORM_VERSION = "${androidPackagesVersions.platform}";

    ANDROID_NDK_PLATFORM = "android-${androidPackagesVersions.platform}";
    ANDROID_NDK_HOST = "linux-x86_64";

    ANDROID_ABI = "x86_64";
  };

  # ===========================================================================

  jdk = pkgs.openjdk8;
  gradle = pkgs.gradle_6;

  # ===========================================================================

  envVarsToShell = envVars:
    lib.concatStringsSep "\n" (
      lib.attrsets.mapAttrsToList (name: value: "export ${name}=${value}") envVars
    )
  ;

  # ===========================================================================

  envVars = androidEnvVars // {
    JDK_PATH = "${jdk.home}";
    JAVA_HOME = "${jdk.home}";
  };

  # ===========================================================================

  configureFlagsSkipList = [
    "qt3d"
    "qtactiveqt"
    # "qtandroidextras"
    # "qtbase"
    "qtcharts"
    # "qtconnectivity"
    "qtdatavis3d"
    # "qtdeclarative"
    "qtdoc"
    "qtgamepad"
    "qtgraphicaleffects"
    # "qtimageformats"
    # "qtlocation"
    "qtlottie"
    "qtmacextras"
    "qtmultimedia"
    # "qtnetworkauth"
    "qtpurchasing"
    "qtquick3d"
    "qtquickcontrols"
    # "qtquickcontrols2"
    "qtquicktimeline"
    "qtremoteobjects"
    "qtscript"
    "qtscxml"
    # "qtsensors"
    "qtserialbus"
    "qtserialport"
    "qtspeech"
    # "qtsvg"
    # "qttools"
    "qttranslations"
    "qtvirtualkeyboard"
    "qtwayland"
    "qtwebchannel"
    "qtwebengine"
    # "qtwebglplugin"
    # "qtwebsockets"
    "qtwebview"
    "qtwinextras"
    "qtx11extras"
    # "qtxmlpatterns"
  ];

  configureFlags = [
    "-opensource"
    "-confirm-license"
    "-release"

    "-shared"
    "-static"

    # "-platform" "linux-clang"
    "-xplatform" "android-clang"

    "-c++std" "c++17"
    "-disable-rpath"
    "-no-pch"
    "-no-warnings-are-errors"

    "-android-sdk" "${androidEnvVars.ANDROID_SDK_ROOT}"
    "-android-ndk" "${androidEnvVars.ANDROID_NDK_ROOT}"
    "-android-ndk-platform" "${androidEnvVars.ANDROID_NDK_PLATFORM}"
    "-android-ndk-host" "${androidEnvVars.ANDROID_NDK_HOST}"
    "-android-abis" "${androidEnvVars.ANDROID_ABI}"
  ] ++ (
    lib.lists.concatMap (x: ["-skip" x]) configureFlagsSkipList
  ) ++ [
    "-nomake" "tests"
    "-nomake" "examples"
  ];

  # ===========================================================================

  script-run-build-drv = pkgs.writeScriptBin "run-build.sh" ''
    set -eu

    args=("$@")

    QT_SRC_DIR="${qt-src}"
    QT_BUILD_DIR=''${QT_BUILD_DIR:-"$PWD"/_build}
    QT_INSTALL_DIR=''${QT_INSTALL_DIR:-"$PWD"/_dest/qt5-for-android/${qt-version}/${androidEnvVars.ANDROID_ABI}}

    MAKE_NJOBS=''${MAKE_NJOBS:-"$(nproc)"}

    ${envVarsToShell envVars}

    configureFlags=(
      -prefix "$QT_INSTALL_DIR"
      ${lib.strings.concatStringsSep " " configureFlags}
    )

    print_env() {
      echo "====================================================="
      declare -p args
      echo "-----------------------------------------------------"
      env | sort
      echo "-----------------------------------------------------"
      echo 'PATH entries:'
      echo $PATH | tr ':' '\n'
      echo "-----------------------------------------------------"
      echo "QT_SRC_DIR=$QT_SRC_DIR"
      echo "QT_BUILD_DIR=$QT_BUILD_DIR"
      echo "QT_INSTALL_DIR=$QT_INSTALL_DIR"
      echo
      echo "MAKE_NJOBS=$MAKE_NJOBS"
      echo
      echo "ANDROID_HOME=$ANDROID_HOME"
      echo "ANDROID_SDK_ROOT=$ANDROID_SDK_ROOT"
      echo "ANDROID_NDK_ROOT=$ANDROID_NDK_ROOT"
      echo "ANDROID_NDK_HOME=$ANDROID_NDK_HOME"
      echo "ANDROID_PLATFORM_VERSION=$ANDROID_PLATFORM_VERSION"
      echo
      echo "JDK_PATH=$JDK_PATH"
      echo "JAVA_HOME=$JAVA_HOME"
      echo "-----------------------------------------------------"
      (set -x && (
        # clang --version
        /bin/pwd --version
        which --version
      ))
      echo "-----------------------------------------------------"
      (set -x && (
        ls --color=always /bin
        ls -la --color=always /usr
        ls --color=always /usr/lib
        ls --color=always /usr/include
      ))
      echo "-----------------------------------------------------"
      declare -p configureFlags
      echo "====================================================="
    }

    print_env


    # clear_qt_dirs() {
    #   rm -rf "$QT_BUILD_DIR" "$QT_INSTALL_DIR"
    # }
    # clear_qt_dirs



    [ ! -d "$QT_BUILD_DIR" ] && mkdir -p "$QT_BUILD_DIR"
    cd "$QT_BUILD_DIR"


    $QT_SRC_DIR/configure "''${configureFlags[@]}"

    # (set +eux && (
    #   $QT_SRC_DIR/configure "''${configureFlags[@]}" -h > _configure_help.txt
    #   $QT_SRC_DIR/configure "''${configureFlags[@]}" -list-libraries &> _configure_help_list-libraries.txt
    #   $QT_SRC_DIR/configure "''${configureFlags[@]}" -list-features &> _configure_help_list-features.txt
    # )) || true


    make -j"$MAKE_NJOBS"

    [ ! -d "$QT_INSTALL_DIR" ] && mkdir -p "$QT_INSTALL_DIR"

    make -j"$MAKE_NJOBS" install

  '';


  qt5-for-android-builder = pkgs.buildFHSEnv {
    name = "qt5-for-android-builder";
    targetPkgs = pkgs: [
      pkgs.coreutils
      pkgs.gnumake

      pkgs.gcc
      pkgs.glibc.static
      pkgs.glibc

      pkgs.which
      pkgs.perl
      pkgs.python39

      jdk
      gradle


      qt-src

      script-run-build-drv
    ];

    runScript = "/bin/run-build.sh";
  };

  # ===========================================================================
in
qt5-for-android-builder
# // { inherit qt-src; }
