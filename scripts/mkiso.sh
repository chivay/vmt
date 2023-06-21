#!/bin/sh
KERNEL_ELF=$1
TMPDIR=$(mktemp -d)

mkdir -p $TMPDIR/boot/grub
cp $KERNEL_ELF $TMPDIR/boot/kernel.elf
cat - ./scripts/grub.cfg <<EOF > $TMPDIR/boot/grub/grub.cfg
set cmdline="${CMDLINE}"
EOF

mkdir -p build

grub-mkrescue -o build/kernel.iso $TMPDIR 2> /dev/null
rm -rf $TMPDIR
