#!/usr/bin/env zsh
set -e
set -u
set -o pipefail

create_tree() {
  if [ -z "$1" ]; then
    echo "Usage: create_tree <branch> [base-branch]" >&2
    return 1
  fi

  local branch="$1"
  local base_branch="${2:-main}"
  local repo_root parent_dir worktree_dir worktree_parent dir_name

  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "create_tree: run inside a git repository" >&2
    return 1
  }

  parent_dir=$(dirname "$repo_root")
  dir_name="${branch##*/}"
  worktree_dir="$parent_dir/$dir_name"
  worktree_parent=$(dirname "$worktree_dir")

  if [ ! -d "$worktree_parent" ]; then
    mkdir -p "$worktree_parent" || {
      echo "create_tree: unable to create parent directory $worktree_parent" >&2
      return 1
    }
  fi

  if [ -d "$worktree_dir" ]; then
    echo "create_tree: $worktree_dir already exists" >&2
    return 1
  fi

  git fetch origin "$base_branch" || return 1

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git worktree add "$worktree_dir" "$branch"
  else
    git worktree add "$worktree_dir" -b "$branch" "origin/$base_branch"
  fi || return 1

  (
    cd "$worktree_dir" || return 1
    local upstream
    upstream=$(git rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null || true)
    if [ "$upstream" != "origin/$branch" ]; then
      if git rev-parse --verify --quiet "origin/$branch"; then
        git branch --set-upstream-to="origin/$branch" "$branch" || {
          echo "create_tree: failed to set upstream to origin/$branch" >&2
          return 1
        }
      else
        git push -u origin "$branch" || {
          echo "create_tree: failed to push branch to origin" >&2
          return 1
        }
      fi
    fi
  ) || return 1

  if [ -f "$repo_root/.env.local" ] && [ ! -f "$worktree_dir/.env.local" ]; then
    cp "$repo_root/.env.local" "$worktree_dir/.env.local" || {
      echo "create_tree: failed to copy .env.local" >&2
      return 1
    }
  fi

  local temporal_env_src="$repo_root/temporal/.env"
  local temporal_env_dest="$worktree_dir/temporal/.env"
  if [ -f "$temporal_env_src" ] && [ ! -f "$temporal_env_dest" ]; then
    mkdir -p "$(dirname "$temporal_env_dest")" || {
      echo "create_tree: failed to create temporal directory" >&2
      return 1
    }
    cp "$temporal_env_src" "$temporal_env_dest" || {
      echo "create_tree: failed to copy temporal/.env" >&2
      return 1
    }
  fi

  if command -v pnpm >/dev/null 2>&1; then
    (cd "$worktree_dir" && pnpm install) || {
      echo "create_tree: pnpm install failed" >&2
      return 1
    }
  else
    echo "create_tree: pnpm not found in PATH" >&2
    return 1
  fi
}

create_tree "$@"
