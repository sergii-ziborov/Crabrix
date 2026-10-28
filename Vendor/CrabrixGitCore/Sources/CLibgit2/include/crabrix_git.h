#ifndef CRABRIX_GIT_NETWORK_H
#define CRABRIX_GIT_NETWORK_H
#include "git2.h"
static inline int crabrix_git_network_limits(void) {
    int code = git_libgit2_opts(GIT_OPT_SET_SEARCH_PATH, GIT_CONFIG_LEVEL_GLOBAL, "");
    if (code < 0) return code;
    code = git_libgit2_opts(GIT_OPT_SET_SEARCH_PATH, GIT_CONFIG_LEVEL_SYSTEM, "");
    if (code < 0) return code;
    code = git_libgit2_opts(GIT_OPT_SET_SEARCH_PATH, GIT_CONFIG_LEVEL_XDG, "");
    if (code < 0) return code;
    code = git_libgit2_opts(GIT_OPT_SET_CACHE_MAX_SIZE, (ssize_t)(16 * 1024 * 1024));
    if (code < 0) return code;
    code = git_libgit2_opts(GIT_OPT_SET_SERVER_CONNECT_TIMEOUT, 10000);
    if (code < 0) return code;
    code = git_libgit2_opts(GIT_OPT_SET_SERVER_TIMEOUT, 10000);
    if (code < 0) return code;
    return git_libgit2_opts(GIT_OPT_SET_PACK_MAX_OBJECT_SIZE, (size_t)(8 * 1024 * 1024));
}
#endif
