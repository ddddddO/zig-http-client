dump_tls:
	zig test src/tls.zig > dump.bin

show_dump:
	od -x dump.bin