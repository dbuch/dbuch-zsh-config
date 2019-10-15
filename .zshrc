fpath+=$HOME/.zfunc

setopt vi
setopt nobeep
setopt

autoload -Uz compinit && compinit
autoload -Uz +X add-zle-hook-widget 2>/dev/null

source $HOME/.zsh/custom_alias.zsh
source $HOME/.cargo/env

#      
#         
#  

#MODE_SYMBOL='❯'
#

#function at_host() {
#  REPLY=${SSH_CONNECTION+@%m}
#}
#grml_theme_add_token at_host -f at_host '' ''

#zstyle ':prompt:grml:left:setup' items rc user at_host path vcs

#zstyle ':prompt:grml:*:items:user' pre '%B%85F'
#zstyle ':prompt:grml:*:items:user' post '%b%f'

#zstyle ':prompt:grml:*:items:path' pre ' %B%75F'
#zstyle ':prompt:grml:*:items:path' post '%b%f'

#zstyle ':prompt:grml:*:items:at_host' pre '%B%75F'
#zstyle ':prompt:grml:*:items:at_host' post '%b%f'

# The following lines were added by compinstall

#zstyle ':completion:*' completer _expand _complete _ignored _correct _approximate
#zstyle :compinstall filename '/home/dbuch/.zshrc'

alias sudo='sudo '

# End of lines added by compinstall
#
# Lines configured by zsh-newuser-install

# End of lines configured by zsh-newuser-install
#

# Ensure precmds are run after cd
local redraw-prompt() {
  local precmd
  for precmd in $precmd_functions; do
    $precmd
  done
  zle reset-prompt
}
zle -N redraw-prompt

bookmarks() {
  setopt localoptions pipefail 2> /dev/null
  local location=$(cat "$BOOKMARKFILE" | sort | sk --reverse --preview 'exa -a --group-directories-first --oneline --git --color=always $(echo {} | sed "s|~|$HOME/|")')
  if [[ -z $location ]]; then
    zle redisplay
    return 0
  fi

  cd `echo "$location" | sed "s|~|$HOME/|"`
  local ret=$?
  zle redraw-prompt
  return $ret
}
zle     -N   bookmarks
bindkey '^b' bookmarks

zsh_grep() {
  local res="$(sk --reverse --ansi -i --height="40%" -c 'rg --color=always --line-number "{}"')"
  if [[ -z $res ]]; then
    zle redisplay
    return 0
  fi

  local file=$(cut -d':' -f1 <<< "$res")
  local lineN=$(cut -d':' -f2 <<< "$res")

  $EDITOR $file +$lineN
  local ret=$?

  zle redraw-prompt

  return $ret
}

zle     -N   zsh_grep
bindkey '^g' zsh_grep

function! bookmark() {
  local bm=`echo $PWD`
  if [[ -z $(grep -x "$bm" $HOME/.bookmarks 2>/dev/null) ]]; then
      echo $bm >> $HOME/.bookmarks
      echo "Bookmark '$bm' saved"
  else
      echo "Bookmark '$bm' existed"
      return 1
  fi
}
