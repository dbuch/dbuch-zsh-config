autoload -Uz compinit && compinit
autoload -U promptinit && promptinit
autoload -Uz +X add-zle-hook-widget 2>/dev/null

export FPATH=/usr/share/zsh/functions/Async/:$FPATH

zmodload zsh/parameter
zmodload zsh/complist
zmodload zsh/deltochar
zmodload zsh/mathfunc

zmodload -ap zsh/mapfile mapfile
zmodload -a  zsh/stat    zstat
zmodload -a  zsh/zpty    zpty

#      
#         
#  

#MODE_SYMBOL='❯'
#
prompt dbuch

# ZSH Options
setopt vi
setopt append_history
setopt extended_history
setopt histignorealldups
setopt histignorespace
setopt auto_cd
setopt extended_glob
setopt longlistjobs
setopt nobeep
setopt notify
setopt completeinword
setopt pushd_ignore_dups
setopt interactivecomments
setopt noglobdots
setopt noshwordsplit
setopt unset

alias sudo='sudo '

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

# Maybe use 'builtin' keyword here for cd?
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

function bookmark() {
  local bm=`echo $PWD`
  if [[ -z $(grep -x "$bm" $HOME/.bookmarks 2>/dev/null) ]]; then
      echo $bm >> $HOME/.bookmarks
      echo "Bookmark '$bm' saved"
  else
      echo "Bookmark '$bm' existed"
      return 1
  fi
}
