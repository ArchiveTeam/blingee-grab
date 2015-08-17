#!/bin/bash
sudo apt-get update
if ! pip show requests 2>/dev/null | grep -q 'Version:'
then
  echo "Installing python-requests"
  sudo pip install requests
fi
if ! dpkg-query -Wf'${Status}' python-lxml 2>/dev/null | grep -q '^i'
then
  echo "Installing python-lxml"
  sudo apt-get -y install python-lxml
fi

exit 0


