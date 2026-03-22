#! /bin/sh
set -e

# variables controlling build
IMAGE=${IMAGE:-container}
PLATFORMS=${PLATFORMS:-"linux/arm64 linux/arm/v7 linux/amd64"}
TAG=${TAG:-$IMAGE-multi}
BUILDX_BUILDER_NAME=routeros-platforms-builder

# verify system
echo "Building multiplatform image for: $PLATFORMS"
echo "Verify docker installation" 
docker info > /dev/null
docker buildx version

# get the list of installed platforms (removing commas to keep sh list)
PLATFORM_NAMES=$(docker buildx ls --format '{{.Name}}')
PLATFORM_LIST=$(docker buildx ls --format '{{.Platforms}}')

# verify platforms are available
for platform in $PLATFORMS; do
    printf '\tChecking buildx has platform: %s\n' "$platform"
    echo "$PLATFORM_LIST" | grep -q "$platform"
    printf '\tVerify buildx has platform: %s\n' "$platform"
done
BUILDX_PLATFORMS=$(echo "$PLATFORMS" | tr ' ' ',')
printf '\tAll platforms found, using buildx platform=%s\n' "$BUILDX_PLATFORMS"

printf '\tRun buildx create to create builder for requested platforms\n'
case "$PLATFORM_NAMES" in
    *"$BUILDX_BUILDER_NAME"*) ;;
    *) docker buildx create --platform="$BUILDX_PLATFORMS" --name "$BUILDX_BUILDER_NAME" ;;
esac

printf '\tRun buildx build to make the actually image\n'
docker buildx build --builder "$BUILDX_BUILDER_NAME" --platform="$BUILDX_PLATFORMS" --output "type=oci,dest=$TAG.tar" --tag "$TAG" .

printf '\tRemove custom multiplatform builder\n'
docker buildx rm "$BUILDX_BUILDER_NAME"

printf '\tls .tar file build\n'
ls -lh "$TAG.tar"

printf '\tCompleted.  Built OCI image: %s%s.tar\n' "$(pwd)" "$TAG"


# Author's Note: Ignore the irony of using a shell script to do a "build" of a Makefile container
