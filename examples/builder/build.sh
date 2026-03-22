#! /bin/sh
set -e

ROSARCH_DEFAULT="arm64 arm x86"
IMAGE=netinstall

ROSARCHARGS="$*"
ROSARCH=${ROSARCH:-${ROSARCHARGS:-$ROSARCH_DEFAULT}}
echo "Starting platform-specific build using $ROSARCH"
for rosarch in $ROSARCH; do 
  TAG=$IMAGE-$rosarch

  case $rosarch in
    arm64) PLATFORMS=linux/arm64 ;;
    arm) PLATFORMS=linux/arm/v7 ;;
    x86) PLATFORMS=linux/amd64 ;;
    *) echo "Bad platform: $rosarch"; exit 1 ;;
  esac

  echo "Build OCI with single, specific-platform using tag $TAG"
  . ./build-multi.sh

  printf '\tCompleted. Built %s platform-specific image: %s%s.tar\n' "$PLATFORMS" "$(pwd)" "$TAG"
done
