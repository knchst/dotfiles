echo "📦  Load zshrc"
# vim:set fdm=marker:
# vim:set ts=8 sts=2 sw=2 tw=0:

export XDG_CONFIG_HOME="$HOME/.config"
export TERM=xterm-256color
export PATH=/usr/local/bin:$PATH
# use key map like emacs
bindkey -e

# append history when exit shell
setopt append_history

# extended format for history
setopt extended_history

# beep when no history
unsetopt hist_beep

# delete duplicated history when register command
setopt hist_ignore_all_dups

# don't register history if the command with leading spaces
setopt hist_ignore_space

# remove extra spaces from command
setopt hist_reduce_blanks

# don't run command when matching
setopt hist_verify

# share history with all zsh process
setopt share_history

# make key map for history search
autoload history-search-end
zle -N history-beginning-search-backward-end history-search-end
zle -N history-beginning-search-forward-end history-search-end
bindkey "^P" history-beginning-search-backward-end
bindkey "^N" history-beginning-search-forward-end


# prompt settings
# variable expansion for prompt
setopt prompt_subst

# expansion of percent for prompt variable
setopt prompt_percent

# output CR when generating characters without trailing CR into prompt
setopt prompt_cr

# visible CR when output CR by prompt_cr
setopt prompt_sp

# completion settings
autoload -Uz compinit
compinit -u
# don't create new prompt
setopt always_last_prompt

# do like putting * on cursor when complement
setopt complete_in_word

# output list automatically
setopt auto_list

# completion when pushed key for complement twice
unsetopt bash_auto_list

# move a command of candidates
setopt auto_menu

# set a command immediately
unsetopt menu_complete

# don't substring alias when complement
setopt complete_aliases

# beep when no result
unsetopt list_beep

# reduce line of list
setopt list_packed

# show trailing character of file
setopt list_types

# set candidate immediately
# zstyle ':completion:*' menu true

zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' use-cache true
zstyle ':completion:*:default' menu select=3
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}

# color settings
autoload -U colors: colors

# auto change directory
setopt auto_cd

# correct command
setopt correct

setopt auto_pushd
setopt cdable_vars
setopt pushd_ignore_dups
setopt auto_param_slash
setopt mark_dirs
setopt auto_param_keys
setopt interactive_comments
setopt magic_equal_subst
setopt print_eight_bit
setopt extended_glob
setopt globdots

#local
[ -f ~/.zshrc.local ] && source ~/.zshrc.local

# brew
brew=`which brew 2>&1`
if [[ $? == 0 ]]; then
  . `brew --prefix`/etc/profile.d/z.sh
fi
function precmd ()
{
  brew=`which brew 2>&1`
  if [[ $? == 0 ]]; then
    _z --add "$(pwd -P)"
  fi
}

# load $HOME/.zsh/*
if [ -d $HOME/.zsh ]; then
  for i in `ls -1 $HOME/.zsh`; do
    echo "📦  Load $i"
    src=$HOME/.zsh/$i; [ -f $src ] && . $src
  done
fi

source ~/.zprofile

SUCCESS='$'
ERROR='$'

APPEND=''
if [ -n "${ON_DOCKER}" ]; then
  APPEND='Attached '
fi
# PROMPT1
PS1="%{[0m%}
%{[31m%}${APPEND}%}
%{[34m%}❯ %M%{[0m%} %{[33m%}❯ %~%{[0m%}
%(?|%{[36m%}${SUCCESS}|%{[31m%}${ERROR})%{[35m%}\$(git_status)\$(parse_git_branch) %{[0m%}"

#%{${DEFAULT} %{[33m%}%~%{[0m%}

# PROMPT3
PS2="%_> "

# PROMPT for correct
SPROMPT="zsh: Did you mean: %{[4m[31m%}%r%{[14m[0m%} [nyae]? "

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

#[[ -n $(which starship) ]] && eval $(starship init zsh)
