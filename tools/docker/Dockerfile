FROM ammo74/netinstall 

ENV ARCH=arm64
ENV PKGS="wifi-qcom container" 
ENV CHANNEL=testing
ENV OPTS="-e"
ENV IFACE=eth0

# OPTIONAL: VER will override CHANNEL

# ENV VER = 7.14.3
# ENV VER_NETINSTALL = 7.14.3
# ENV CLIENTIP = 172.17.0.101

# NOTE: For custom package, like branding, place file next to Dockerfile and copy:

# ENV PKGS_CUSTOM = "mybranding.npk"
# COPY mybranding.npk .

RUN make download 

