# im-maliit -- GTK4 input method module for Maliit (GTK4 port)
#
#   make                       build for the host
#   make CC=aarch64-linux-gnu-gcc PKG_CONFIG_LIBDIR=... im-maliit.so
#
# For Ubuntu Touch you want an aarch64 build. The simplest route is a container
# with GTK4 arm64 development files; see README.md.

CC      ?= cc
PKG     ?= pkg-config
CFLAGS  += -O2 -Wall -fPIC $(shell $(PKG) --cflags gtk4)
LDLIBS  += $(shell $(PKG) --libs gtk4 gio-2.0)

all: libim-maliit.so

libim-maliit.so: im-maliit.c
	$(CC) -shared $(CFLAGS) -o $@ $< $(LDLIBS)

clean:
	rm -f libim-maliit.so

.PHONY: all clean
