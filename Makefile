# im-maliit -- GTK3 input method module for Maliit
#
#   make                       build for the host
#   make CC=aarch64-linux-gnu-gcc PKG_CONFIG_LIBDIR=... im-maliit.so
#
# For Ubuntu Touch you want an aarch64 build. The simplest route is a container
# with GTK3 arm64 development files; see README.md.

CC      ?= cc
PKG     ?= pkg-config
CFLAGS  += -O2 -Wall -fPIC $(shell $(PKG) --cflags gtk+-3.0)
LDLIBS  += $(shell $(PKG) --libs gtk+-3.0 gio-2.0)

# Where GTK looks for input method modules on this system.
IMDIR   ?= $(shell $(PKG) --variable=libdir gtk+-3.0)/gtk-3.0/3.0.0/immodules

all: im-maliit.so

im-maliit.so: im-maliit.c
	$(CC) -shared $(CFLAGS) -o $@ $< $(LDLIBS)

# System-wide install, for a distribution or a rootfs you control. Click apps
# should instead ship the module inside the package; see README.md.
install: im-maliit.so
	install -Dm755 im-maliit.so $(DESTDIR)$(IMDIR)/im-maliit.so
	@echo "Now regenerate the cache:  gtk-query-immodules-3.0 --update-cache"

clean:
	rm -f im-maliit.so

.PHONY: all install clean
