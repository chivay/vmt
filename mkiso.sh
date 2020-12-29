#!/bin/sh
set -e
zig build

BUILD_DIR=build/x86_64

TMPDIR=$(mktemp -d)

mkdir -p $TMPDIR/boot/grub
cp $BUILD_DIR/kernel $TMPDIR/boot/kernel.elf
cp grub.cfg $TMPDIR/boot/grub/grub.cfg
grub-mkrescue -o kernel.iso $TMPDIR 2> /dev/null


rm -rf $TMPDIR
