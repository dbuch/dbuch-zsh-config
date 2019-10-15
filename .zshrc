#
# User configuration sourced by interactive shells
#
fpath+=$HOME/.zfunc

autoload -Uz compinit && compinit
autoload -Uz +X add-zle-hook-widget 2>/dev/null

setopt vi

source /home/dbuch/.zsh/custom_alias.zsh
source /home/dbuch/.cargo/env
source /usr/share/skim/key-bindings.zsh
source /usr/share/skim/completion.zsh

#      
#         
#  

#MODE_SYMBOL='❯'
#
export EDITORCMD=nvim
export DIFFPROG='nvim -d'

function at_host() {
  REPLY=${SSH_CONNECTION+@%m}
}
grml_theme_add_token at_host -f at_host '' ''

zstyle ':prompt:grml:left:setup' items rc user at_host path vcs

zstyle ':prompt:grml:*:items:user' pre '%B%85F'
zstyle ':prompt:grml:*:items:user' post '%b%f'

zstyle ':prompt:grml:*:items:path' pre ' %B%75F'
zstyle ':prompt:grml:*:items:path' post '%b%f'

zstyle ':prompt:grml:*:items:at_host' pre '%B%75F'
zstyle ':prompt:grml:*:items:at_host' post '%b%f'

# The following lines were added by compinstall

zstyle ':completion:*' completer _expand _complete _ignored _correct _approximate
zstyle :compinstall filename '/home/dbuch/.zshrc'

alias sudo='sudo '

# End of lines added by compinstall
#
# Lines configured by zsh-newuser-install
HISTFILE=~/.histfile
HISTSIZE=1000
SAVEHIST=1000
# End of lines configured by zsh-newuser-install
#

skim-bookmarks-widget() {
  local selected num
  setopt localoptions noglobsubst noposixbuiltins pipefail 2> /dev/null
  selected=( $(fc -rl 1 | SKIM_DEFAULT_OPTIONS="--height -40%" sk)  )
  local ret=$?
  if [ -n "$selected" ]; then
    num=$selected[1]
    if [ -n "$num" ]; then
      zle vi-fetch-history -n $num
    fi
  fi
  zle reset-prompt
  return $ret
}

# CTRL-R - Paste the selected command from history into the command line
skim-history-widget() {
  local selected num
  setopt localoptions noglobsubst noposixbuiltins pipefail 2> /dev/null
  selected=( $(fc -rl 1 |
    SKIM_DEFAULT_OPTIONS="--reverse --height ${SKIM_TMUX_HEIGHT:-40%} $SKIM_DEFAULT_OPTIONS -n2..,.. --tiebreak=index $SKIM_CTRL_R_OPTS --query=${(qqq)LBUFFER} -m" $(__skimcmd)) )
  local ret=$?
  if [ -n "$selected" ]; then
    num=$selected[1]
    if [ -n "$num" ]; then
      zle vi-fetch-history -n $num
    fi
  fi
  zle reset-prompt
  return $ret
}
zle     -N   skim-history-widget
bindkey '^R' skim-history-widget

bookmarks() {
  setopt localoptions noglobsubst noposixbuiltins pipefail 2> /dev/null
  local cur_path=$(cat $HOME/.bookmarks | sort | sk --height="40%" --reverse)
  if [[ -n $cur_path ]]; then
    cd $cur_path &&
  fi
  zle reset-prompt
}
zle     -N   bookmarks
bindkey '^b' bookmarks

function! bookmark() {
  local bm=`echo $PWD | sed 's|~|$HOME|'`
  if [[ -z $(grep "$bm" $HOME/.bookmarks 2>/dev/null) ]]; then
      echo $bm >> $HOME/.bookmarks
      echo "Bookmark '$bm' saved"
  else
      echo "Bookmark already existed"
      return 1
  fi
}
