all: iso

kernel:
	cargo build --manifest-path=./kernel/Cargo.toml --target=./kernel/x86_64-vmt.json -Z build-std=core,compiler_builtins

boot.o: ./boot/boot.asm
	nasm -f elf64 ./boot/boot.asm -o boot.o

kernel.elf: boot.o ./layout.ld ./kernel/target/x86_64-vmt/debug/libkernel.a
	ld -n -T ./layout.ld -o kernel.elf boot.o ./kernel/target/x86_64-vmt/debug/libkernel.a
	grub-file --is-x86-multiboot kernel.elf

iso: grub.cfg kernel.elf grub.cfg
	@mkdir -p iso/boot/grub
	@cp kernel.elf iso/boot/kernel.elf
	@cp grub.cfg iso/boot/grub/grub.cfg
	grub-mkrescue -o kernel.iso iso

run: iso
	qemu-system-x86_64 -cdrom ./kernel.iso -serial stdio -m 1024M

debug: iso
	qemu-system-x86_64 -s -cdrom ./kernel.iso -serial stdio -m 1024M


clean:
	rm -rf boot.o kernel.elf kernel.iso iso/

.PHONY: kernel iso run clean
