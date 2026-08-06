# OpenCode worktree helper (personal) — sourced from ~/.zshrc
# claude -w / ccw 相当
#
#   ocww                        # 自動名 (adj-name-hex) → .worktrees/<name> → opencode
#   ocww <name>                 # 明示名
#   ocww -b branch [name]
#   ocww --no-setup [name]
#   ocwwc [name]                # shell only
#   cd "$(_opencode_worktree [name])"

_opencode_worktree() {
  emulate -L zsh
  setopt err_return no_unset pipefail
  # allow empty name during parse
  setopt localoptions unset

  local log die
  log() { print -u2 -- "$*"; }
  die() { log "error: $*"; return 1; }

  local name="" branch=""
  local base_ref="${OPENCODE_W_BASE:-origin/main}"
  local worktree_root_rel="${OPENCODE_W_ROOT:-.worktrees}"
  local do_fetch=1 do_setup=1 do_open=0 do_cd=0
  local open_cmd="${OPENCODE_W_OPEN:-opencode}"
  local exec_cmd=""
  local main_root worktree_parent worktree_path

  usage() {
    print -u2 -- "ocww — OpenCode worktree (claude -w style) for mori

Usage:
  ocww [options] [name]           # name 省略時は自動生成 (adj-scientist-hex)
  ocww [options] -b <branch> [name]
  ocwwc [options] [name]          # shell only

Options:
  -b, --branch <branch>  Branch to checkout (create from base if missing)
  --base <ref>           Base ref (default: origin/main)
  --root <dir>           Worktree parent (default: .worktrees)
  --no-fetch             Skip git fetch
  --no-setup             Skip mise/local-file/deps setup
  --open [cmd]           Launch cmd after setup (default: opencode)
  --cd                   Exec shell in worktree after setup
  -e, --exec <cmd>       Run cmd in worktree after setup
  -h, --help             Show help"
  }

  # claude -w 風: adjective-scientist-hex6
  _ocww_random_hex() {
    local hex=""
    if command -v openssl >/dev/null 2>&1; then
      hex="$(openssl rand -hex 3 2>/dev/null || true)"
    fi
    if [[ -z "$hex" ]] && [[ -r /dev/urandom ]]; then
      hex="$(LC_ALL=C tr -dc 'a-f0-9' </dev/urandom | head -c 6)"
    fi
    if [[ -z "$hex" ]]; then
      hex="$(printf '%06x' "$(( RANDOM * RANDOM % 16777216 ))")"
    fi
    print -r -- "$hex"
  }

  _ocww_generate_name() {
    local -a adjs names
    adjs=(
      agile amber brisk calm clever cosmic crisp eager earnest electric
      fluent focused gentle glad golden humble icy jolly keen lucid
      merry nimble noble placid plucky proud quick quiet rapid rusty
      sharp silent silver sleek snappy solar spry steady stellar swift
      tidy vivid warm witty zen
    )
    names=(
      ada bohr curie darwin dirac euclid euler fermat fourier gauss
      hamilton hermite hilbert hopper huygens jung kepler knuth lagrange
      laplace lovelace maxwell newton noether ohm pascal pauli planck
      poincare ramanujan riemann turing volta vonneumann watt wright
    )
    local adj name hex candidate
    local parent="$1"
    local tries=0
    while (( tries < 32 )); do
      adj="${adjs[RANDOM % $#adjs + 1]}"
      name="${names[RANDOM % $#names + 1]}"
      hex="$(_ocww_random_hex)"
      candidate="${adj}-${name}-${hex}"
      if [[ ! -e "$parent/$candidate" ]] \
        && ! git -C "$main_root" show-ref --verify --quiet "refs/heads/$candidate" 2>/dev/null; then
        print -r -- "$candidate"
        return 0
      fi
      tries=$((tries + 1))
    done
    # last resort
    print -r -- "wt-$(date +%Y%m%d-%H%M%S)-$(_ocww_random_hex)"
  }

  while (( $# > 0 )); do
    case "$1" in
      -h|--help) usage; return 0 ;;
      -b|--branch)
        (( $# >= 2 )) || { die "$1 requires an argument"; return 1; }
        branch="$2"; shift 2 ;;
      --base)
        (( $# >= 2 )) || { die "$1 requires an argument"; return 1; }
        base_ref="$2"; shift 2 ;;
      --root)
        (( $# >= 2 )) || { die "$1 requires an argument"; return 1; }
        worktree_root_rel="$2"; shift 2 ;;
      --no-fetch) do_fetch=0; shift ;;
      --no-setup) do_setup=0; shift ;;
      --open)
        do_open=1
        if (( $# >= 2 )) && [[ "$2" != -* ]]; then
          open_cmd="$2"; shift 2
        else
          shift
        fi ;;
      --cd) do_cd=1; shift ;;
      -e|--exec)
        (( $# >= 2 )) || { die "$1 requires an argument"; return 1; }
        exec_cmd="$2"; shift 2 ;;
      --) shift; break ;;
      -*) die "unknown option: $1 (try --help)"; return 1 ;;
      *)
        if [[ -z "$name" ]]; then
          name="$1"
        else
          die "unexpected argument: $1"; return 1
        fi
        shift ;;
    esac
  done

  # main repo root from any linked worktree
  local common toplevel first
  toplevel="$(git rev-parse --show-toplevel 2>/dev/null)" || { die "not inside a git repository"; return 1; }
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
    || common="$(git rev-parse --git-common-dir)"
  if [[ -d "$common" && "$(basename "$common")" == ".git" ]]; then
    main_root="$(cd "$(dirname "$common")" && pwd)"
  else
    first="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree / {print substr($0, 10); exit}')"
    if [[ -n "$first" ]]; then
      main_root="$(cd "$first" && pwd)"
    else
      main_root="$(cd "$toplevel" && pwd)"
    fi
  fi
  [[ -d "$main_root" ]] || { die "could not resolve main repo root"; return 1; }

  worktree_parent="$main_root/$worktree_root_rel"
  mkdir -p "$worktree_parent"

  local auto_named=0
  # name も branch も無し → claude -w 同様に自動生成
  if [[ -z "$name" && -z "$branch" ]]; then
    name="$(_ocww_generate_name "$worktree_parent")"
    branch="$name"
    auto_named=1
    log "auto name: $name"
  elif [[ -z "$branch" ]]; then
    branch="$name"
  elif [[ -z "$name" ]]; then
    name="${branch//\//-}"
    name="$(print -r -- "$name" | tr -cs 'A-Za-z0-9._-' '-')"
    name="${name#-}"
    name="${name%-}"
  fi

  if [[ "$name" == */* || "$name" == "." || "$name" == ".." ]]; then
    die "name must be a single directory segment (got: $name)"; return 1
  fi

  worktree_path="$worktree_parent/$name"

  if [[ -e "$worktree_path" ]]; then
    if (( auto_named )); then
      # 衝突時は再生成（通常は generator 側で回避済み）
      name="$(_ocww_generate_name "$worktree_parent")"
      branch="$name"
      worktree_path="$worktree_parent/$name"
      log "auto name retry: $name"
    fi
    if [[ -e "$worktree_path" ]]; then
      die "path already exists: $worktree_path"; return 1
    fi
  fi

  if [[ "$worktree_root_rel" == ".worktrees" ]]; then
    if ! git -C "$main_root" check-ignore -q ".worktrees" 2>/dev/null; then
      log "warning: .worktrees is not gitignored — add it to .gitignore"
    fi
  fi

  if (( do_fetch )); then
    log "git fetch origin ..."
    if [[ "$base_ref" == origin/* ]]; then
      git -C "$main_root" fetch origin "${base_ref#origin/}"
    else
      git -C "$main_root" fetch origin
    fi
  fi

  if ! git -C "$main_root" rev-parse --verify --quiet "$base_ref" >/dev/null; then
    die "base ref not found: $base_ref (try without --no-fetch)"; return 1
  fi

  # git progress → stderr so stdout stays path-only
  if git -C "$main_root" show-ref --verify --quiet "refs/heads/$branch"; then
    log "using existing local branch: $branch"
    git -C "$main_root" worktree add "$worktree_path" "$branch" >&2
  elif git -C "$main_root" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    log "creating local branch from origin/$branch"
    git -C "$main_root" worktree add -b "$branch" "$worktree_path" "origin/$branch" >&2
  else
    log "creating new branch $branch from $base_ref"
    git -C "$main_root" worktree add -b "$branch" "$worktree_path" "$base_ref" >&2
  fi

  worktree_path="$(cd "$worktree_path" && pwd)"
  log "worktree created: $worktree_path"
  log "branch: $(git -C "$worktree_path" branch --show-current 2>/dev/null || print -r -- "$branch")"

  if (( do_setup )); then
    # .worktreeinclude copy (same intent as repo hooks)
    local include_file="$main_root/.worktreeinclude"
    if [[ -f "$include_file" ]]; then
      local rel src dst
      while IFS= read -r rel || [[ -n "$rel" ]]; do
        rel="${rel%%#*}"
        rel="${rel##[[:space:]]}"
        rel="${rel%%[[:space:]]}"
        [[ -n "$rel" ]] || continue
        src="$main_root/$rel"
        dst="$worktree_path/$rel"
        [[ "$src" == "$dst" ]] && continue
        if [[ -d "$src" ]]; then
          if [[ -e "$dst" ]]; then
            log "skip copy dir $rel (already exists)"
            continue
          fi
          log "copying dir $rel ..."
          mkdir -p "$(dirname "$dst")"
          if cp -a -c "$src" "$dst" 2>/dev/null; then
            :
          elif command -v rsync >/dev/null 2>&1; then
            mkdir -p "$dst"
            rsync -a "$src"/ "$dst"/
          else
            cp -a "$src" "$dst"
          fi
          log "copied dir $rel"
        elif [[ -f "$src" ]]; then
          mkdir -p "$(dirname "$dst")"
          cp "$src" "$dst"
          log "copied $rel"
        else
          log "skip $rel (not in main repo)"
        fi
      done < "$include_file"
    fi

    local setup_script="$main_root/.codex/hooks/setup-worktree.sh"
    if [[ -f "$setup_script" ]]; then
      log "running setup-worktree.sh ..."
      MORI_SOURCE_REPO="$main_root" \
        CODEX_WORKTREE_PATH="$worktree_path" \
        bash "$setup_script" >/dev/null
    else
      log "warning: missing $setup_script"
    fi

    if command -v mise >/dev/null 2>&1 && [[ -f "$worktree_path/mise.toml" ]]; then
      log "mise trust ..."
      (cd "$worktree_path" && mise trust -y "$worktree_path/mise.toml") || true
      log "mise install ..."
      (cd "$worktree_path" && mise install) || log "warning: mise install failed (non-fatal)"
    elif ! command -v mise >/dev/null 2>&1; then
      log "warning: mise not on PATH; skipped mise install"
    fi

    local schema_dir="$worktree_path/apps/api/schema"
    if [[ -f "$schema_dir/package.json" && ! -d "$schema_dir/node_modules" ]]; then
      log "npm ci apps/api/schema ..."
      if command -v mise >/dev/null 2>&1; then
        (cd "$schema_dir" && mise exec -- npm ci)
      else
        (cd "$schema_dir" && npm ci)
      fi
    fi
    log "setup complete"
  else
    log "skipped setup (--no-setup)"
  fi

  print -r -- "$worktree_path"

  if [[ -n "$exec_cmd" ]]; then
    log "exec: $exec_cmd"
    (cd "$worktree_path" && bash -lc "$exec_cmd")
  fi

  if (( do_open )); then
    if ! command -v "$open_cmd" >/dev/null 2>&1; then
      die "open command not found: $open_cmd"; return 1
    fi
    log "opening: $open_cmd (cwd=$worktree_path)"
    if (( do_cd )); then
      cd "$worktree_path" || return 1
      exec "$open_cmd"
    else
      (cd "$worktree_path" && exec "$open_cmd")
    fi
  elif (( do_cd )); then
    log "entering shell in $worktree_path"
    cd "$worktree_path" || return 1
    # stay in this shell (no exec) so nested shell isn't required
    return 0
  fi
}

# claude -w 相当
ocww()  { _opencode_worktree --open "$@"; }
ocwwc() { _opencode_worktree --cd "$@"; }
