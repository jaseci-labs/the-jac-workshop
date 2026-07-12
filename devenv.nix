{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:

let
  # Runtime libraries that pre-built Python wheels (numpy/scipy/pandas/pyod)
  # dynamically load but that NixOS shells don't expose by default.
  # Confirmed missing via `ldd .jac/venv/.../numpy/_core/_multiarray_umath.so`:
  #   libstdc++.so.6 => not found        # numpy's C++ code
  #   libz.so.1      => not found        # deflate; pandas / matplotlib pull it
  runtimeLibs = with pkgs; [
    stdenv.cc.cc.lib   # libstdc++.so.6, libgcc_s.so.1
    zlib               # libz.so.1
  ];
in
{
  packages = [
    # Regular (non-free-threaded) Python 3.14.
    #
    # jac's binary embeds libpython3.14.so built with the regular ABI.
    # The system default python3 on this host is 3.14 free-threaded (`3.14t`),
    # whose C-extension wheels (`.cpython-314t.so`) can't be loaded by jac's
    # embedded runtime. Seeding each project's `.jac/venv` with THIS Python
    # produces matching wheels, so numpy/pandas/pyod import cleanly under
    # `jac start`.
    pkgs.python314

    pkgs.git
  ] ++ runtimeLibs;

  # NixOS doesn't put library dirs on LD_LIBRARY_PATH the way FHS distros do,
  # so pre-built manylinux wheels can't dlopen libstdc++/libz. Expose them
  # explicitly so `import numpy` (and everything downstream) works.
  env.LD_LIBRARY_PATH = lib.makeLibraryPath runtimeLibs;

  # Convenience script: recreate a project's Jac venv against this Python.
  # Usage from inside a project dir:  seed-jac-venv
  scripts.seed-jac-venv = {
    description = "Recreate ./.jac/venv against the devenv's regular Python 3.14 (run from a project subdir).";
    exec = ''
      set -euo pipefail
      if [ ! -f jac.toml ]; then
        echo "seed-jac-venv: no jac.toml in $(pwd) — cd into a Jac project first." >&2
        exit 1
      fi
      rm -rf .jac/venv
      mkdir -p .jac
      python3 -m venv .jac/venv
      echo "seeded .jac/venv with $(python3 --version)"
      echo "next: 'jac install' to populate deps from jac.toml,"
      echo "      or 'jac install pandas statsmodels pyod byllm' to add them explicitly."
    '';
  };

  enterShell = ''
    echo ""
    echo "jaseci_workshop_codes dev shell"
    echo "  python: $(python3 --version)"
    echo ""
    echo "Per-project first-run setup (from the project dir, e.g. metrics-workbench/):"
    echo "  seed-jac-venv   # recreate .jac/venv against this Python"
    echo "  jac install     # populate deps"
    echo ""
  '';
}
