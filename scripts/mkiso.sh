#!/bin/sh
KERNEL_ELF=$1
TMPDIR=$(mktemp -d)

mkdir -p $TMPDIR/boot/grub
cp $KERNEL_ELF $TMPDIR/boot/kernel.elf
cp grub.cfg $TMPDIR/boot/grub/grub.cfg
grub-mkrescue -o $(dirname $KERNEL_ELF)/kernel.iso $TMPDIR 2> /dev/null
rm -rf $TMPDIR
