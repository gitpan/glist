/****
* GLIST - LIST MANAGER
* ============================================================
* FILENAME
*       gfetch-wrapper.c
* PURPOSE
*       Make a wrapper to gfetch for systems not supporting
*       suidperl
* AUTHORS
*       Ask Solem Hoel <ask@unixmonks.net>
* ============================================================
* This file is a part of the glist mailinglist manager.
* (c) 2001 Ask Solem Hoel <http://www.unixmonks.net>
*
* This program is free software; you can redistribute it and/or modify
* it under the terms of the GNU General Public License version 2
* as published by the Free Software Foundation.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program; if not, write to the Free Software
* Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
*/

#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>
#include "include/glist.h"

#ifndef CMD
  #define CMD "/bin/gfetch"
#endif

int main(int argc, char *argv[]) {
	extern int errno;
	int exec_status;
	char gfetch[1024];
	

	strncat(gfetch, CMD, sizeof(gfetch));
	exec_status = execv(gfetch, argv);
	if(exec_status < 0) {
                printf("Error: %s: %s\n", strerror(errno), gfetch);
                return 1;
        }
        else {
                return 0;
        };
}
