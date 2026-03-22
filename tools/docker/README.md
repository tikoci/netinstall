# Building the `netinstall` image locally

The following mini-project has an **example** `Dockerfile` and build scripts that shows how to customize `netinstall` using a local build.

### _Example:_ Building packages into the container at build time

This example shows downloading the package for "offline" use.

The `Dockerfile` shows using `ENV` to set the netinstall options built into the container, using the DockerHub version as the "base image".  Additional, the example shows `make download`, which causes the RouterOS packages to be downloaded.  Those packages will be part of the image, so if `netinstall-*.tar` is used on RouterOS, no downloading or even any /container/env should be needed - the values will come from your customized `Dockerfile` here.

> [!TIP]
>
> The `Dockerfile`'s  variable have the same maining as described in the project [`README.md`](../../README.md).  You can add other `make` commands, and/or remove the `make download` if you want too.

#### Customizing the `Dockerfile`

The example `Dockerfile` just downloads one image, based on ARCH=arm64 being set.  But, further customization is possible with more `RUN make`.  Including running `make`multiple times to add more packages to be built into image (rather than default image which also downloads what it needs on-demand).  The default `Dockerfile` looks like:

```dockerfile
FROM ammo74/netinstall
ENV ARCH=arm64
ENV PKGS="wifi-qcom container"
ENV CHANNEL=testing
ENV OPTS="-e"

RUN make download
```

So possible to add a couple more lines at bottometo also download images for "arm" and "tile" to build into an `tar` image.

```dockerfile
RUN make download ARCH=arm
RUN make download ARCH=tile
```

Or perhaps use all also include a specific versions:

```dockerfile
RUN make download ARCH=arm64 VER=7.12.1
RUN make download ARCH=tile VER=7.12.1
RUN make download ARCH=arm VER=7.12.1
```

> [!NOTE]
>
> To use the additionally downloaded package, `ARCH` need to be set in `/container/env` before container is started.  There is only one default `ARCH`, which is based on what set in the `ENV` in `Dockerfile` **unless** overriden in `/container/env`.  Why specifying ARCH=arm64 in above example is unneeded.
>

### Build using `docker buildx`

There are many ways to build containers.  Here [Docker Desktop](https://www.docker.com/products/docker-desktop/) is assumed.

The basic command is just:

```sh
docker buildx build --platform=linux/arm64 --output "type=oci,dest=mynetinstall.tar" --tag mynetinstall .
```

And if familar with containization, it's not hard.

#### Using `./build.sh` Build Scripts

To build the image, there is `./build.sh` to build three `tar` files, one for each RouterOS architecutre that supports `/container`.

If you need to build the `Dockerfile`, for one platform just provide the RouterOS architecutre name:

```sh
./build.sh arm64
```

Valid architecture values are "arm64", "arm", and "x86" - these values apply to the /container - the container can contain packages for **any** architecture.

> [!NOTE]
>
> `./build-multi.sh` is the main builder - it does the "heavy lifting" to _actually_ build the packages from `./build.sh`.  But using all three support platforms in one "multi-platform" image is far from idea here.  _i.e._ The image file be **huge** if _all packages_ for _all platforms_ were used with the `make download` in the example.
