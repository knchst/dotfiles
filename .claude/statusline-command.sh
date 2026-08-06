#!/bin/bash
set -f

input=$(cat)

# ── Colors ──────────────────────────────────────────────
green='\033[1;32m'
red='\033[1;31m'
cyan='\033[0;36m'
blue='\033[1;34m'
yellow='\033[0;33m'
magenta='\033[0;35m'
dim='\033[2m'
reset='\033[0m'

# ── Extract data ─────────────────────────────────────────
cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // ""')
[ -z "$cwd" ] || [ "$cwd" = "null" ] && cwd=$(pwd)
dirname=$(basename "$cwd")

model=$(echo "$input" | jq -r '.model.display_name // .model.id // ""')
# Shorten model name
case "$model" in
  *opus*4.6*|*Opus*4.6*)   model="opus-4.6" ;;
  *opus*4*|*Opus*4*)       model="opus-4" ;;
  *sonnet*4.6*|*Sonnet*4.6*) model="sonnet-4.6" ;;
  *sonnet*4*|*Sonnet*4*)   model="sonnet-4" ;;
  *haiku*4.5*|*Haiku*4.5*) model="haiku-4.5" ;;
  *haiku*|*Haiku*)         model="haiku" ;;
  ""|"null")               model="" ;;
esac

ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
ctx_pct=$(printf "%.0f" "$ctx_pct" 2>/dev/null || echo "0")

cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
cost=$(printf "%.2f" "$cost" 2>/dev/null || echo "0.00")

duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
if [ "$duration_ms" != "0" ] && [ "$duration_ms" != "null" ]; then
  duration_s=$((duration_ms / 1000))
  hours=$((duration_s / 3600))
  mins=$(( (duration_s % 3600) / 60 ))
  if [ "$hours" -gt 0 ]; then
    duration="${hours}h${mins}m"
  else
    duration="${mins}m"
  fi
else
  duration=""
fi

lines_add=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
lines_del=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')

worktree=$(echo "$input" | jq -r '.worktree.name // ""')

# ── Git info ─────────────────────────────────────────────
git_branch=""
git_dirty=0
if git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
    if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
        git_dirty=1
    fi
fi

# ── Context bar color ────────────────────────────────────
if [ "$ctx_pct" -ge 80 ]; then
  ctx_color="$red"
elif [ "$ctx_pct" -ge 50 ]; then
  ctx_color="$yellow"
else
  ctx_color="$green"
fi

# ── Build output ─────────────────────────────────────────
# Line 1: arrow + dir + git
arrow="${green}➜${reset}"
dir_part="${cyan}${dirname}${reset}"

git_part=""
if [ -n "$git_branch" ]; then
    if [ "$git_dirty" -eq 1 ]; then
        git_part=" ${blue}git:(${red}${git_branch}${blue})${reset} ${yellow}✗${reset}"
    else
        git_part=" ${blue}git:(${red}${git_branch}${blue})${reset}"
    fi
fi

worktree_part=""
if [ -n "$worktree" ] && [ "$worktree" != "null" ]; then
    worktree_part=" ${magenta}[wt:${worktree}]${reset}"
fi

line1="${arrow}  ${dir_part}${git_part}${worktree_part}"

# Line 2: model | context | cost | duration | lines
parts=()

if [ -n "$model" ]; then
    parts+=("${magenta}${model}${reset}")
fi

parts+=("${dim}ctx:${reset}${ctx_color}${ctx_pct}%${reset}")

if [ "$cost" != "0.00" ]; then
    parts+=("${dim}\$${reset}${yellow}${cost}${reset}")
fi

if [ -n "$duration" ]; then
    parts+=("${dim}${duration}${reset}")
fi

if [ "$lines_add" != "0" ] || [ "$lines_del" != "0" ]; then
    parts+=("${green}+${lines_add}${reset}${dim}/${reset}${red}-${lines_del}${reset}")
fi

line2=""
for i in "${!parts[@]}"; do
    if [ "$i" -gt 0 ]; then
        line2+=" ${dim}|${reset} "
    fi
    line2+="${parts[$i]}"
done

printf "%b\n%b" "$line1" "$line2"

exit 0
