CC = gcc
CFLAGS = -O2 -pedantic -fPIC -Wall -Werror -Wmissing-prototypes 

all: gfetch-wrapper gdefer-wrapper gcmd-wrapper

gfetch-wrapper: gfetch-wrapper.c

gfetch-wrapper.c: 
	$(CC) $(CFLAGS) $? -o gfetch-wrapper

gdefer-wrapper: gdefer-wrapper.c

gdefer-wrapper.c: 
	$(CC) $(CFLAGS) $? -o gdefer-wrapper

gcmd-wrapper: gcmd-wrapper.c

gcmd-wrapper.c:
	$(CC) $(CFLAGS) $? -o gcmd-wrapper

clean:
	-rm -f gcmd-wrapper gdefer-wrapper gfetch-wrapper *.o core a.out
