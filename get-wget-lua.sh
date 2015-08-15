#!/usr/bin/env bash
#
# This script downloads and compiles wget-lua.
#

# first, try to detect gnutls or openssl
CONFIGURE_SSL_OPT=""
if builtin type -p pkg-config &>/dev/null
then
  if pkg-config gnutls
  then
    echo "Compiling wget with GnuTLS."
    CONFIGURE_SSL_OPT="--with-ssl=gnutls"
  elif pkg-config openssl
  then
    echo "Compiling wget with OpenSSL."
    CONFIGURE_SSL_OPT="--with-ssl=openssl"
  fi
fi
cd get-wget-lua.tmp
if ./configure $CONFIGURE_SSL_OPT --disable-nls && make && src/wget -V | grep -q lua
then
  cp src/wget ../wget-lua
  cd ../
  echo
  echo
  echo "###################################################################"
  echo
  echo "wget-lua successfully built."
  echo
  ./wget-lua --help | grep -iE "gnu|warc|lua"
  rm -rf get-wget-lua.tmp
  exit 0
else
  echo
  echo "wget-lua not successfully built."
  echo
  exit 1
fi
