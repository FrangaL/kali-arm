#!/bin/bash -ex

# Check compatible systems.
if ! which dpkg > /dev/null; then
   echo "Script only compatible with Debian-based systems"
   exit 1
fi

deps="qemu-user-static binfmt-support curl"
for pkg in $deps; do
  if [[ $(dpkg -l $pkg | awk '/^ii/ { print $1 }') != ii ]]; then
    apt-get -y $pkg
  fi
done

compose_release() {
  curl --silent "https://api.github.com/repos/docker/compose/releases/latest" |
  grep -Po '"tag_name": "\K.*?(?=")'
}

if ! [ -x "$(command -v docker-compose)" ]; then
  curl -L https://github.com/docker/compose/releases/download/$(compose_release)/docker-compose-$(uname -s)-$(uname -m) \
  -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose
fi

docker-compose --compatibility up -d --build

# docker-compose down --remove-orphans
