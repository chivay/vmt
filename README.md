# vmt
![CI](https://github.com/chivay/vmt/workflows/CI/badge.svg)

Toy OS written in Zig ;)
Requires Zig from master.

## Contribute

Send your patches to `~chivay/public-inbox@lists.sr.ht`

## How to
```bash
$ zig build qemu
[Info] x86: CPU Vendor: GenuineIntel
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
[Info] x86.mm: Detected 1022MiB of free memory
[Info] kernel.mm: VirtualAddress{ffff800000000000} -> PhysicalAddress{0} (0x40000000 bytes)
[Info] kernel.mm: VirtualAddress{ffffffff80000000} -> PhysicalAddress{0} (0x200000 bytes)
[Info] x86.mm: Memory subsystem initialized
[Info] x86.trampoline: Initializing trampolines
[Info] x86.acpi: Initializing ACPI
[Info] x86.acpi: Valid RSDP found
[Info] x86.acpi: Found table FACP
[Info] x86.acpi: Found table APIC
[Info] x86.acpi: Found table HPET
[Info] x86.acpi: Found table MCFG
[Info] x86.acpi: Found table WAET
[Info] x86.apic: Initializing APIC
[Info] x86.apic: LAPIC is at PhysicalAddress{fee00000}
[Info] x86.apic: LAPIC ID 0
[Info] x86.pci: Initializing PCI
[Info] x86.pci: 00.00.0 Device 8086:29c0
[Info] x86.pci: 00.01.0 Device 1234:1111
[Info] x86.pci: 00.02.0 Device 8086:10d3
[Info] x86.pci: 00.1f.0 Device 8086:2918
[Info] x86.pci: 00.1f.2 Device 8086:2922
[Info] x86.pci: 00.1f.3 Device 8086:2930
[Info] x86.smp: Performing AP startup code relocation
[Info] x86.smp: CPU1 up
[Info] x86.smp: CPU2 up
....
```
