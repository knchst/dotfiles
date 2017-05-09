## docker
alias dl='docker ps -l -q'
alias da='docker ps -a'
alias dat='docker attach `dl`'

## bear
alias bear='~/dotfiles/scripts/bear.swift'

alias ce='cd ../'
alias ls='ls -F -G'
alias la='ls -a -G'
alias ll='ls -la -G'
alias sl="ls"

alias grep='grep --color=always'
alias ngrep='grep -n --color=always'
alias fgrep='fgrep --color=always'
alias egrep='egrep --color=always'

alias less='less -R'

# haskell-sktack
alias ghc="stack ghc"
alias ghci="stack ghci"
alias runghc="stack runghc"
alias runhaskell="stack runghc"

# alias for vim
alias vi='vim -u $HOME/.virc'
sw_vers=`which sw_vers 2>&1`
if [[ $? == 0 ]]; then
    alias vim='/Applications/MacVim.app/Contents/MacOS/Vim'
fi