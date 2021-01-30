# vmt
![CI](https://github.com/chivay/vmt/workflows/CI/badge.svg)

Toy OS written in Zig ;)

## How to
```bash
$ zig build qemu
[Debug] x86: CR3: 0x102000
[Info] x86: CPU Vendor: GenuineIntel
[Debug] x86: Kernel end: VirtualAddress{ffffffff80125000}
[Info] x86: Booting the kernel...
[Info] x86.mm: BIOS memory map:
[Info] x86.mm: [0000000000-000009fbff] Available
[Info] x86.mm: [000009fc00-000009ffff] Reserved
[Info] x86.mm: [00000f0000-00000fffff] Reserved
[Info] x86.mm: [0000100000-003ffdefff] Available
[Info] x86.mm: [003ffdf000-003fffffff] Reserved
[Info] x86.mm: [00b0000000-00bfffffff] Reserved
[Info] x86.mm: [00fed1c000-00fed1ffff] Reserved
[Info] x86.mm: [00feffc000-00feffffff] Reserved
[Info] x86.mm: [00fffc0000-00ffffffff] Reserved
...
```
