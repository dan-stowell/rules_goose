/* The C side of walk.goose's directory listing. Goose's own list_dir
   follows symlinks when asked whether an entry is a directory, and joins the
   names with newlines; the walk needs each entry's type as lstat sees it,
   and every name, whatever bytes it holds. */
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

/* Appends every entry of the directory `dir` but . and .. to the builder
   out, unsorted, as a type byte, the name and a NUL: 'd' for a directory,
   'f' for a regular file, 'o' for anything else (a symlink, a FIFO, a
   socket, a device, or an entry gone before it could be looked at).
   Returns 1, or 0 if the directory could not be read. */
static int32_t c_list_dir(sl_u8 dir, gs_rref out) {
    char *path = malloc((size_t)dir.len + 1);
    if (path == NULL) return 0;
    memcpy(path, dir.data, (size_t)dir.len);
    path[dir.len] = 0;
    DIR *d = memchr(path, 0, (size_t)dir.len) ? NULL : opendir(path);
    free(path);
    if (d == NULL) return 0;
    int ok = 1;
    for (;;) {
        errno = 0;
        struct dirent *e = readdir(d);
        if (e == NULL) { ok = errno == 0; break; }
        const char *name = e->d_name;
        if (name[0] == '.' && (!name[1] || (name[1] == '.' && !name[2]))) continue;
        struct stat st;
        char kind = 'o';
        if (fstatat(dirfd(d), name, &st, AT_SYMLINK_NOFOLLOW) == 0) {
            if (S_ISDIR(st.st_mode)) kind = 'd';
            else if (S_ISREG(st.st_mode)) kind = 'f';
        }
        gs_bld_append(out, &kind, 1);
        gs_bld_append(out, name, strlen(name) + 1);
    }
    closedir(d);
    return ok;
}
