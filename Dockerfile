FROM kalilinux/kali-rolling

ENV LC_ALL C
ENV DEBIAN_FRONTEND noninteractive

ARG APT_OPTS="--no-install-recommends -o APT::Install-Suggests=0"

RUN set -eux; \
      { \
        echo 'path-exclude /lib/systemd/system/multi-user.target.wants/*'; \
        echo 'path-exclude /etc/systemd/system/*.wants/*'; \
        echo 'path-exclude /lib/systemd/system/local-fs.target.wants/*'; \
        echo 'path-exclude /lib/systemd/system/sockets.target.wants/*udev*'; \
        echo 'path-exclude /lib/systemd/system/sockets.target.wants/*initctl*'; \
        echo 'path-exclude /lib/systemd/system/sysinit.target.wants/systemd-tmpfiles-setup*'; \
        echo 'path-exclude /lib/systemd/system/systemd-update-utmp*'; \
        echo 'path-exclude /etc/systemd/system/sysinit.target.wants/systemd-timesyncd.*'; \
        echo 'path-exclude /etc/systemd/system/dbus-org.freedesktop.timesync1.*'; \
        echo 'path-exclude /usr/lib/systemd/system/systemd-logind.*'; \
      } > /etc/dpkg/dpkg.cfg.d/50-no_systemd-files

RUN apt-get update \
    && apt-get install -y $APT_OPTS ca-certificates wget procps dbus kmod udev git \
    libterm-readline-gnu-perl systemd systemd-sysv systemd-container \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/cache/apt/*.bin \
    /var/lib/dpkg/*-old /var/cache/debconf/*-old /var/cache/apt/archives/*

# RUN rm -f /lib/systemd/system/multi-user.target.wants/* \
#       /etc/systemd/system/*.wants/* \
#       /lib/systemd/system/local-fs.target.wants/* \
#       /lib/systemd/system/sockets.target.wants/*udev* \
#       /lib/systemd/system/sockets.target.wants/*initctl* \
#       /lib/systemd/system/sysinit.target.wants/systemd-tmpfiles-setup* \
#       /lib/systemd/system/systemd-update-utmp*

RUN git clone --depth 1 --single-branch --branch master https://gitlab.com/kalilinux/build-scripts/kali-arm.git /kali

# Install depencecies
# RUN /kali/build-deps.sh \
#     rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/cache/apt/*.bin \
#     /var/lib/dpkg/*-old /var/cache/debconf/*-old /var/cache/apt/archives/*

WORKDIR /kali

VOLUME [ "/sys/fs/cgroup" ]

CMD [ "/lib/systemd/systemd" ]
