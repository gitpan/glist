#include <stdio.h>
#include <stdlib.h>
#include <pwd.h>
#include <sys/types.h>

int
main(int argc, char *argv[])
{
	char username[2048];
	struct passwd *pw;

	if(argc <= 1) {
		fprintf(stderr, "Usage: %s username\n", argv[0]);
		return 0;
	}
	snprintf(username, sizeof(username), "%s", (char *)argv[1]);
	if((pw = getpwnam(username)) != NULL) {
		printf("%d\n", pw->pw_gid);
		return 0;
	}
	else {
		fprintf(stderr, "No such user: %s\n", username);
		return 1;
	}
}
