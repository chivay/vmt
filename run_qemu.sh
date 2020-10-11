#!/bin/bash

DISP=$1
if [ "$1" == "" ]; then
    DISP="none"
fi

qemu-system-x86_64 -cdrom kernel.iso \
                   -serial stdio \
                   -display $DISP \
                   -enable-kvm \
                   -s \
                   $2
