#!/bin/bash
if ! dpkg-query -Wf'${Status}' luarocks 2>/dev/null | grep -q '^i'
then
  echo "Installing luarocks"
  sudo apt-get update
  sudo apt-get -y install luarocks
  echo "Installing LuaRock htmlparser"
  sudo luarocks install htmlparser
fi

exit 0

