// Test-only CRT fault injection. It never changes user documents or keys.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <io.h>
#include <share.h>
#include <stdio.h>
#include <errno.h>
static int close_calls, held_fd=-1;
static int fail_commit(int fd) { held_fd=fd; errno=EIO; return -1; }
static int record_close(int fd) { close_calls++; held_fd=-1; return _close(fd); }
#define _commit fail_commit
#define _close record_close
#define main product_cli_main
#include "slh_product_cli.c"
#undef main
#undef _close
#undef _commit
int main(void) {
    char path[128]; int result, left_open, exists;
    const unsigned char data[4]={1,2,3,4};
    snprintf(path,sizeof(path),"review-commit-failure-%lu.tmp",GetCurrentProcessId());
    if(_access(path,0)==0) return 2;
    result=write_new(path,data,sizeof(data));
    left_open=(close_calls!=1); exists=(_access(path,0)==0);
    // Clean up only the file/descriptor this test created, even on failure.
    if(held_fd>=0) _close(held_fd);
    if(exists) _unlink(path);
    if(result!=-1 || left_open || exists) {
        fprintf(stderr,"FAIL: commit-error cleanup result=%d close_calls=%d file_remained=%d\n",result,close_calls,exists);
        return 1;
    }
    puts("EXCLUSIVE WRITE COMMIT-FAILURE CLEANUP TEST PASSED");return 0;
}
