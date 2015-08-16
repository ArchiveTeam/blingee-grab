#!/bin/bash
sudo apt-get update
if ! dpkg-query -Wf'${Status}' luarocks 2>/dev/null | grep -q '^i'
then
  echo "Installing luarocks"
  sudo apt-get -y install luarocks
  echo "Installing LuaRock htmlparser"
  sudo luarocks install htmlparser
fi
if ! dpkg-query -Wf'${Status}' python-requests 2>/dev/null | grep -q '^i'
then
  echo "Installing python-requests"
  sudo apt-get -y install python-requests
fi
if ! dpkg-query -Wf'${Status}' python-lxml 2>/dev/null | grep -q '^i'
then
  echo "Installing python-lxml"
  sudo apt-get -y install python-lxml
fi

exit 0


