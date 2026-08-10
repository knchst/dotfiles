# Interactive shell settings

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# Emacs-style key bindings
bindkey -e

# History
HISTFILE="$HOME/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000
setopt append_history
setopt extended_history
setopt hist_ignore_all_dups
setopt hist_ignore_space
setopt hist_reduce_blanks
setopt share_history
unsetopt hist_beep

# Search history using the current input as a prefix
autoload -Uz history-search-end
zle -N history-beginning-search-backward-end history-search-end
zle -N history-beginning-search-forward-end history-search-end
bindkey '^P' history-beginning-search-backward-end
bindkey '^N' history-beginning-search-forward-end

# Completion
autoload -Uz compinit
compinit
setopt complete_in_word
setopt auto_list
setopt auto_menu
unsetopt list_beep
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*:default' menu select=3

# Convenient interactive behavior
setopt auto_cd
setopt auto_pushd
setopt pushd_ignore_dups
setopt interactive_comments

# Machine-specific settings such as Kaku and OpenCode belong here.
[[ -r "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

# Kaku shell integration
[[ -r "$HOME/.config/kaku/zsh/kaku.zsh" ]] && source "$HOME/.config/kaku/zsh/kaku.zsh"

# Optional fzf integration
[[ -r "$HOME/.fzf.zsh" ]] && source "$HOME/.fzf.zsh"
