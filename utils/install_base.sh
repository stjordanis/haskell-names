cabal install --package-db=../packages.db --haskell-suite -w hs-gen-iface --gcc-option=-I/usr/lib/ghc/include --extra-include-dirs=/usr/lib/ghc/include --solver=topdown --force-reinstalls -v3 -f include-ghc-prim