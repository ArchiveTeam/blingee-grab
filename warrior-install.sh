#!/bin/bash
sudo apt-get update
if ! pip search requests 2>/dev/null | grep -q -z1 -Poi "\- Python HTTP for Humans.[\s]*INSTALLED"
then
  echo "Installing python-requests"
  sudo pip install requests
fi
if ! dpkg-query -Wf'${Status}' python-lxml 2>/dev/null | grep -q '^i'
then
  echo "Installing python-lxml"
  sudo apt-get -y install python-lxml
fi
if ! dpkg-query -Wf'${Status}' python-crypto 2>/dev/null | grep -q '^i'
then
  echo "Installing python-crypto"
  sudo apt-get -y install python-crypto
fi

exit 0


