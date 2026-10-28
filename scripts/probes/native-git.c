/* Qualification probe only. Not linked into the shipping app. */
#include <git2.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

static void check(int result, const char *operation) {
    if (result < 0) {
        const git_error *error = git_error_last();
        fprintf(stderr, "%s: %s\n", operation, error ? error->message : "unknown Git error");
        exit(1);
    }
}
static void write_file(const char *root, const char *path, const void *data, size_t size) {
    char full[4096]; snprintf(full,sizeof(full),"%s/%s",root,path);
    FILE *file=fopen(full,"wb"); if (!file) { perror(full); exit(1); }
    if (fwrite(data,1,size,file)!=size || fclose(file)) exit(1);
}
static void commit(git_repository *repo, const char *message, git_oid *oid) {
    git_index *index=NULL; git_tree *tree=NULL; git_signature *author=NULL;
    git_oid tree_id; git_commit *parent=NULL; git_reference *head=NULL;
    check(git_repository_index(&index,repo),"index");
    check(git_index_write_tree(&tree_id,index),"tree");
    check(git_tree_lookup(&tree,repo,&tree_id),"lookup tree");
    check(git_signature_new(&author,"Crabrix Probe","probe@example.invalid",1793203200,0),"author");
    int exists=git_repository_head(&head,repo)==0;
    if (exists) check(git_commit_lookup(&parent,repo,git_reference_target(head)),"parent");
    const git_commit *parents[1]={parent};
    check(git_commit_create(oid,repo,"HEAD",author,author,NULL,message,tree,exists?1:0,parents),"commit");
    git_commit_free(parent);git_reference_free(head);git_signature_free(author);git_tree_free(tree);git_index_free(index);
}

static int transfer(const git_indexer_progress *progress, void *payload) {
    time_t started=*(time_t*)payload;
    return progress->received_bytes>16*1024*1024 || difftime(time(NULL),started)>60 ? GIT_EUSER : 0;
}

int main(int argc, char **argv) {
    if (argc!=2 && argc!=3) return 2;
    check(git_libgit2_init(),"init library");
    if (argc==3) {
        if(strcmp(argv[2],"--public-https"))return 2;
        time_t started=time(NULL);
        git_clone_options options=GIT_CLONE_OPTIONS_INIT;
        options.checkout_opts.checkout_strategy=GIT_CHECKOUT_NONE;
        options.fetch_opts.callbacks.transfer_progress=transfer;
        options.fetch_opts.callbacks.payload=&started;
        git_repository *cloned=NULL;
        check(git_clone(&cloned,"https://github.com/octocat/Hello-World.git",argv[1],&options),"HTTPS clone with system certificate verification");
        git_reference *head=NULL;check(git_repository_head(&head,cloned),"remote HEAD");
        char oid[GIT_OID_HEXSZ+1];git_oid_tostr(oid,sizeof(oid),git_reference_target(head));
        printf("{\"nativeIOSHTTPSClone\":true,\"head\":\"%s\",\"TLS\":\"SecureTransport default verification\",\"checkout\":false}\n",oid);
        git_reference_free(head);git_repository_free(cloned);git_libgit2_shutdown();return 0;
    }
    git_repository *repo=NULL;git_index *index=NULL;git_status_list *status=NULL;
    check(git_repository_init(&repo,argv[1],0),"init repo");
    const char *rust="fn main(){println!(\"native git\");}\n";
    const char *hidden="max_width=100\n";
    const unsigned char binary[]={0,255,128,65,0,13};
    write_file(argv[1],"main.rs",rust,strlen(rust));
    write_file(argv[1],".rustfmt.toml",hidden,strlen(hidden));
    write_file(argv[1],"asset.bin",binary,sizeof(binary));
    check(git_repository_index(&index,repo),"index");
    check(git_index_add_bypath(index,"main.rs"),"stage source");
    check(git_index_add_bypath(index,".rustfmt.toml"),"stage hidden");
    check(git_index_add_bypath(index,"asset.bin"),"stage binary");
    check(git_index_write(index),"write index");git_index_free(index);
    git_oid initial,next;commit(repo,"Initial native iOS commit",&initial);
    write_file(argv[1],"main.rs","fn main(){}\n",12);
    write_file(argv[1],"untracked.txt","pending\n",8);
    git_status_options options=GIT_STATUS_OPTIONS_INIT;
    options.flags=GIT_STATUS_OPT_INCLUDE_UNTRACKED|GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS;
    check(git_status_list_new(&status,repo,&options),"status");
    size_t count=git_status_list_entrycount(status);
    if(count!=2) {fprintf(stderr,"unexpected status count %zu\n",count);return 1;}
    git_status_list_free(status);
    git_commit *first=NULL;git_reference *branch=NULL;
    check(git_commit_lookup(&first,repo,&initial),"lookup initial");
    check(git_branch_create(&branch,repo,"practice",first,0),"branch");
    git_reference_free(branch);
    check(git_repository_index(&index,repo),"index");
    check(git_index_add_bypath(index,"main.rs"),"stage changed source");
    check(git_index_write(index),"write selected index");git_index_free(index);
    commit(repo,"Only selected source",&next);
    git_tree *tree=NULL;check(git_commit_tree(&tree,first),"first tree");
    git_checkout_options checkout=GIT_CHECKOUT_OPTIONS_INIT;
    checkout.checkout_strategy=GIT_CHECKOUT_SAFE;
    check(git_checkout_tree(repo,(git_object*)tree,&checkout),"safe checkout");
    check(git_repository_set_head(repo,"refs/heads/practice"),"switch branch");
    git_tree_free(tree);git_commit_free(first);git_repository_free(repo);
    check(git_repository_open(&repo,argv[1]),"reopen history");
    git_revwalk *walk=NULL;check(git_revwalk_new(&walk,repo),"history");
    check(git_revwalk_push(walk,&next),"history next");
    git_oid item;int commits=0;while(git_revwalk_next(&item,walk)==0)commits++;
    if(commits!=2)return 1;
    git_revwalk_free(walk);git_repository_free(repo);git_libgit2_shutdown();
    printf("{\"nativeIOSGit\":true,\"commits\":2,\"statusEntries\":2,\"selectedCommit\":true,\"branchSwitch\":true,\"reopened\":true}\n");
    return 0;
}
