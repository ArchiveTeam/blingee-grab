#!/bin/bash
sudo apt-get update
if ! dpkg-query -Wf'${Status}' liblua5.2-dev 2>/dev/null | grep -q '^i'
then
  echo "Installing liblua5.2-dev, luarocks for Lua 5.2, and htmlparser"
  sudo apt-get -y install lua5.1-dev lua5.2 liblua5.2-dev git build-essential
  wget http://luarocks.org/releases/luarocks-2.1.1.tar.gz
  tar xzf luarocks-2.1.1.tar.gz
  cd luarocks-2.1.1/
  ./configure \
   --lua-version=5.2 --lua-suffix=5.2 \
   --with-lua-include=/usr/include/lua5.2 --versioned-rocks-dir --force-config
  make build
  sudo make install
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


