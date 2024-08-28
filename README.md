# GitOps demo of Gateway API

This repo describes a demonstration of Gateway API using GitOps patterns.
The commits used in the demo are already present in a source repo, leaving the demonstrator to the task of showing how the file changes in the individual commits enact a desired outcome.

The demonstration is based on a simplified version of [this workshop](https://github.com/solo-io/workshops/tree/381cba9229dbd0c1ff132dbbdb5362c793f13dbe/gloo-gateway/1-17/enterprise/default).

## Tools and prerequisites

You'll need some tools to be able to give this demonstration:

* A Kubernetes cluster that you can access via `kubectl`, `curl`, and your web browser
* A Git server accessible from both your system and the Kubernetes cluster. In this example I use a [Gitea](https://gitea.com) deployed in the Kubernetes cluster itself
* A Git-based continuous delivery tool like Argo CD, configured to sync a repo to the Kubernetes cluster
* A desktop Git tool that will help make it easier to talk about Git and show off changes and commits ([GitHub Desktop](https://desktop.github.com/download/) is good for this and doesn't require your repo to have anything to do with GitHub)

You will also need the [`argocd` CLI tool](https://argo-cd.readthedocs.io/en/stable/cli_installation/) and, if demonstrating rollouts, the [Argo Rollouts kubectl plugin](https://argo-rollouts.readthedocs.io/en/stable/installation/#kubectl-plugin-installation).

The [deploy-git-tools.sh](/deploy-git-tools.sh) script will deploy Gitea and Argo CD, create a working repo synced with a remote on Gitea, and configure Argo CD to sync that remote repo to the cluster.

## Check out commits from a source repo but actually put the files in a working repo

This repo comes with another Git repo that already has a set of commits that show the GitOps demo – simply unzip [source.tar.gz](/source.tar.gz?raw=1).
However, the goal of your demo is probably not to walk through each commit in an existing repo, but rather to show how to:

1. Make a change to the declared state
1. Commit it to a repo
1. Push that repo to a remote Git server
1. See how that commit is synced to a Kubernetes cluster

For this reason it's a good idea to initialise a new Git repo for the demo, and use the directory of this repo as the working copy for the source repo.

This gives us two repos (aside from this one) to think about:

* The _source_ repo, which already has a complete history of the commits you will make in the process of your demo, with each commit tagged for simplicity
* The _working_ repo, which is where you will make new commits as part of the demo and push to a remote that is synced with your cluster.

When working with the _source_ repo, set the `GIT_WORK_TREE` environment variable so that files get checked out to the _working_ repo:

```bash
export GIT_WORK_TREE=path/to/working/repo
```

Now, when you check out commits in the source repo, the changed files themselves will be applied in the working repo directory, allowing you to display the changes that you're making and commit/push them as part of your demo flow.

Take a look at [init-working-repo.sh](/init-working-repo.sh) for an example of how to initialise a new working directory that is preconfigured with a remote.

## Git aliases

An effective way to demo the GitOps approach is to have a small terminal window open in the source repo directory where you can rapidly check out the next commit in the sequence you're demonstrating.
Make sure this terminal window has the `GIT_WORK_TREE` environment variable set to the working repo, as described above.

You can use Git aliases to help with this.
For example, use `start` to check out the commit with tag `1`; use `git next-tag` to check out the commit that has the next numeric tag up from the most recent tag you checked out; and use `git prev-tag` to check out the previous tagged commit.
It's important to make sure your tags are set up correctly for this to work; see the steps below for tips on how to create the tags.

If you're checking these commits out to a different Git repo as described above, you'll be able to see the changes in the commit as unstaged changes in that other repo.

> :sunglasses: It also has the handy benefit of allowing you to see in the terminal the commit message corresponding to the change you're about to make, allowing you to add helpful prompts into the commit message if needed.

You define these aliases in your `~/.gitconfig`:

```ini
[alias]
  start = "!f() { \
    baseTag='1'; \
    startTag=$1; \
    selectedTag=${startTag:-${baseTag:-startTag}}; \
    git reset --hard $selectedTag; \
    git clean -df; \
    git --no-pager tag -l $selectedTag -n999; \
  }; f"
  next-tag = "!f() { \
    tagNum=$(git tag -l --points-at head); \
    nextInt=$(printf '%d' "\""$tagNum"\""); \
    nextTag=$((nextInt+1)); \
    git start $nextTag;\
  }; f"
  prev-tag = "!f() { \
    tagNum=$(git tag -l --points-at head); \
    nextInt=$(printf '%d' "\""$tagNum"\""); \
    nextTag=$((nextInt-1)); \
    git start $nextTag; \
  }; f"
```

(h/t to <https://blog.kieranties.com/2019/04/06/git-next>)

You can further reduce the footprint of this small terminal window by removing everything from the prompt, for example by setting:

```bash
export PS1="❯ "
```

## Tag all commits

If you need to re-tag the source repo for use with these aliases, first delete any existing tags and then run the following to tag all commits on the branch with an incrementing numerical tag (i.e. `1`, `2`, ...)

```shell
tagname=1
while read -r rev; do
    ((tagname++))
    git tag $tagname $rev
done < <(git rev-list tags/1...tags/end --reverse)
```

Note that you shouldn't have any reason to tag commits in the working repo.

## Remove all tags

If you need to reset the tagging scheme in the source schema, for example after modifying older commits, remove all tags with this command:

```shell
git tag | xargs git tag -d
```
