## docker
alias dl='docker ps -l -q'
alias da='docker ps -a'
alias dat='docker attach `dl`'

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

alias simgif="~/Developer/knchst/dotfiles/scripts/sim-gif.sh"