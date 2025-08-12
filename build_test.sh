#!/bin/bash
cd /home/marcilunga/dev/vsec/src
source ~/.opam/opam-init/init.sh 
eval $(opam env) 
dune build 2>&1 | head -10