CC = gcc
CFLAGS = -O2 -pedantic -fPIC -Wall -Werror -Wmissing-prototypes 
DIRS = src
#PREFIX = /opt/glist
all:
	for d in $(DIRS); do \
                (cd $$d; $(MAKE) $(MFLAGS) all) \
                || case "$(MFLAGS)" in *k*) fail=yes;; *) exit 1;; esac; \
        done && test -z "$$fail"

clean:
	for d in $(DIRS); do \
                (cd $$d; $(MAKE) $(MFLAGS) clean) \
                || case "$(MFLAGS)" in *k*) fail=yes;; *) exit 1;; esac; \
        done && test -z "$$fail"

install: all
	cp -f src/gfetch-wrapper src/gcmd-wrapper src/gdefer-wrapper $(PREFIX)/bin
	chmod 4555 $(PREFIX)/bin/gfetch-wrapper
	chmod 4555 $(PREFIX)/bin/gdefer-wrapper
	chmod 4555 $(PREFIX)/bin/gcmd-wrapper
	-chmod 755 $(PREFIX)/bin/gcmd $(PREFIX)/bin/gdefer $(PREFIX)/bin/gdefer
