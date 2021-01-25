# Docker container to build arm images.

Make container docker.
```bash
git clone --single-branch --branch docker \
  https://gitlab.com/kalilinux/build-scripts/kali-arm.git docker

cd docker

./build.sh
```

Make image.
```bash
# Update git files.
docker exec -it kali-builder git pull

# Install depencecies.
docker exec -it kali-builder ./build-deps.sh

# Compile image.
docker exec -it kali-builder bash -c "debug=true ./rpi3-64.sh 2020.4"
```

Copy image out of container.
```bash
# List images compiled.
docker exec -it kali-builder sh -c "ls -la *.xz"

#Copy image out of container.
docker cp kali-builder:/kali/kali-linux-2020.4-rpi4-nexmon-64.img.xz .
```
