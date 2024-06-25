
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = inputs @ { self, nixpkgs, ... }:

  let
    system = "x86_64-linux";

    pkgs = import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
        android_sdk.accept_license = true;
      };
    };

    qt5-for-android-builder = pkgs.callPackage ./default.nix {};
  in
  {

    packages.x86_64-linux = {
      inherit qt5-for-android-builder;
    };
    packages.x86_64-linux.default = qt5-for-android-builder;

  }
  # // { inherit qt5-for-android-builder; }
  ;
}
