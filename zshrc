#############################
# Exports
#############################

export FPATH=/usr/share/zsh/functions/Async:$FPATH
export PAGER=${PAGER:-less}
export EDITOR=${PAGER:-vi}
export LESS_TERMCAP_mb=$'\E[01;31m'
export LESS_TERMCAP_md=$'\E[01;31m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;44;33m'
export LESS_TERMCAP_ue=$'\E[0m'
export LESS_TERMCAP_us=$'\E[01;32m'
export COLORTERM="yes"
export KEYTIMEOUT=1

#############################
# Autoloads
#############################

autoload -Uz compinit && compinit
autoload -Uz add-zle-hook-widget
autoload -Uz edit-command-line
autoload -U promptinit && promptinit
autoload -U async && async

#############################
# ZSH Modules
#############################

zmodload zsh/parameter
zmodload zsh/complist
zmodload zsh/deltochar
zmodload zsh/mathfunc

zmodload -ap zsh/mapfile mapfile
zmodload -a  zsh/stat    zstat
zmodload -a  zsh/zpty    zpty

#############################
# Prompt
#############################

prompt dbuch

#############################
# ZSH Options
#############################

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
setopt nohup
setopt completeinword
setopt pushd_ignore_dups
setopt hash_list_all
setopt interactivecomments
setopt noglobdots
setopt noshwordsplit
setopt unset
setopt correct

#############################
# Types
#############################

typeset -ga ls_options
typeset -ga grep_options

ls_options+=( --color=auto --group-directories-first )
grep_options+=( --color=auto )

#############################
# Alias
#############################

alias sudo='sudo '

alias ls="command ls ${ls_options:+${ls_options[*]}}"
alias la="command ls -la ${ls_options:+${ls_options[*]}}"
alias ll="command ls -l ${ls_options:+${ls_options[*]}}"
alias lh="command ls -hAl ${ls_options:+${ls_options[*]}}"
alias l="command ls -l ${ls_options:+${ls_options[*]}}"
alias grep="command rg ${grep_options:+${grep_options[*]}}"

#############################
# Functions
#############################

# Ensure precmds are run after cd
local redraw-prompt() {
  local precmd
  for precmd in $precmd_functions; do
    $precmd
  done
  zle reset-prompt
}

function skim-history() {
  local selected num
  setopt localoptions noglobsubst noposixbuiltins pipefail 2> /dev/null
  selected=( $(fc -rl 1 |
    SKIM_DEFAULT_OPTIONS="--reverse --height ${SKIM_TMUX_HEIGHT:-40%} $SKIM_DEFAULT_OPTIONS -n2..,.. --tiebreak=index $SKIM_CTRL_R_OPTS --query=${(qqq)LBUFFER} -m" sk) )
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

function skim-bookmarks() {
  setopt localoptions pipefail 2> /dev/null
  local location=$(cat "$BOOKMARKFILE" | sort | sk --reverse --preview 'exa -a --group-directories-first --oneline --git --color=always $(echo {} | sed "s|~|$HOME/|")')
  if [[ -z $location ]]; then
    zle redisplay
    return 0
  fi

  cl `echo "$location" | sed "s|~|$HOME/|"`
  local ret=$?
  zle redraw-prompt
  return $ret
}

function skim_grep() {
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

function cl () {
    emulate -L zsh
    cd $1 && ls -a
}

# smart cd function, allows switching to /etc when running 'cd /etc/fstab'
function cd () {
    if (( ${#argv} == 1 )) && [[ -f ${1} ]]; then
        [[ ! -e ${1:h} ]] && return 1
        print "Correcting ${1} to ${1:h}"
        builtin cd ${1:h}
    else
        builtin cd "$@"
    fi
}

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

#############################
# Zsh Widgets
#############################

zle -N skim-bookmarks
zle -N redraw-prompt
zle -N skim-grep
zle -N skim-history
zle -N edit-command-line

#############################
# Keybindings
#############################

bindkey -v

bindkey -M vicmd 'j' up-line-or-history
bindkey -M vicmd 'k' down-line-or-history
bindkey -M vicmd '^v' edit-command-line

bindkey -M vicmd '^g' zsh_grep
bindkey '^g' skim-grep

bindkey -M vicmd '^b' bookmarks
bindkey '^b' skim-bookmarks

bindkey -M vicmd '^r' skim-history
bindkey '^r' skim-history

#############################
# Completion system
#############################

# allow one error for every three characters typed in approximate completer
zstyle ':completion:*:approximate:'    max-errors 'reply=( $((($#PREFIX+$#SUFFIX)/3 )) numeric )'

# don't complete backup files as executables
zstyle ':completion:*:complete:-command-::commands' ignored-patterns '(aptitude-*|*\~)'

# start menu completion only if it could find no unambiguous initial string
zstyle ':completion:*:correct:*'       insert-unambiguous true
zstyle ':completion:*:corrections'     format $'%{\e[0;31m%}%d (errors: %e)%{\e[0m%}'
zstyle ':completion:*:correct:*'       original true

# activate color-completion
zstyle ':completion:*:default'         list-colors ${(s.:.)LS_COLORS}

# format on completion
zstyle ':completion:*:descriptions'    format $'%{\e[0;31m%}completing %B%d%b%{\e[0m%}'

# automatically complete 'cd -<tab>' and 'cd -<ctrl-d>' with menu
# zstyle ':completion:*:*:cd:*:directory-stack' menu yes select

# insert all expansions for expand completer
zstyle ':completion:*:expand:*'        tag-order all-expansions
zstyle ':completion:*:history-words'   list false

# activate menu
zstyle ':completion:*:history-words'   menu yes

# ignore duplicate entries
zstyle ':completion:*:history-words'   remove-all-dups yes
zstyle ':completion:*:history-words'   stop yes

# match uppercase from lowercase
zstyle ':completion:*'                 matcher-list 'm:{a-z}={A-Z}'

# separate matches into groups
zstyle ':completion:*:matches'         group 'yes'
zstyle ':completion:*'                 group-name ''

zstyle ':completion:*'                 menu select=5

zstyle ':completion:*:messages'        format '%d'
zstyle ':completion:*:options'         auto-description '%d'

# describe options in full
zstyle ':completion:*:options'         description 'yes'

# on processes completion complete all user processes
zstyle ':completion:*:processes'       command 'ps -au$USER'

# offer indexes before parameters in subscripts
zstyle ':completion:*:*:-subscript-:*' tag-order indexes parameters

# provide verbose completion information
zstyle ':completion:*'                 verbose true

zstyle ':completion:*:-command-:*:'    verbose false

# set format for warnings
zstyle ':completion:*:warnings'        format $'%{\e[0;31m%}No matches for:%{\e[0m%} %d'

# define files to ignore for zcompile
zstyle ':completion:*:*:zcompile:*'    ignored-patterns '(*~|*.zwc)'
zstyle ':completion:correct:'          prompt 'correct to: %e'

# Ignore completion functions for commands you don't have:
zstyle ':completion::(^approximate*):*:functions' ignored-patterns '_*'

# Provide more processes in completion of programs like killall:
zstyle ':completion:*:processes-names' command 'ps c -u ${USER} -o command | uniq'

# complete manual by their section
zstyle ':completion:*:manuals'         separate-sections true
zstyle ':completion:*:manuals.*'       insert-sections   true
zstyle ':completion:*:man:*'           menu yes select

# Search path for sudo completion
zstyle ':completion:*:sudo:*'          command-path /usr/local/sbin \
                                                    /usr/local/bin  \
                                                    /usr/sbin       \
                                                    /usr/bin        \
                                                    /sbin           \
                                                    /bin            \
                                                    /usr/X11R6/bin

# provide .. as a completion
zstyle ':completion:*' special-dirs ..

# run rehash on completion so new installed program are found automatically:
function _force_rehash () {
    (( CURRENT == 1 )) && rehash
    return 1
}

zstyle -e ':completion:*' completer '
    if [[ $_last_try != "$HISTNO$BUFFER$CURSOR" ]] ; then
        _last_try="$HISTNO$BUFFER$CURSOR"
        reply=(_complete _match _ignored _prefix _files)
    else
        if [[ $words[1] == (rm|mv) ]] ; then
            reply=(_complete _files)
        else
            reply=(_oldlist _expand _force_rehash _complete _ignored _correct _approximate _files)
        fi
    fi'

# command for process lists, the local web server details and host completion
zstyle ':completion:*:urls' local 'www' '/var/www/' 'public_html'

COMP_CACHE_DIR=${COMP_CACHE_DIR:-${ZDOTDIR:-$HOME}/.cache}
if [[ ! -d ${COMP_CACHE_DIR} ]]; then
    command mkdir -p "${COMP_CACHE_DIR}"
fi
zstyle ':completion:*' use-cache  yes
zstyle ':completion:*:complete:*' cache-path "${COMP_CACHE_DIR}"

# host completion
[[ -r ~/.ssh/config ]] && _ssh_config_hosts=(${${(s: :)${(ps:\t:)${${(@M)${(f)"$(<$HOME/.ssh/config)"}:#Host *}#Host }}}:#*[*?]*}) || _ssh_config_hosts=()
[[ -r ~/.ssh/known_hosts ]] && _ssh_hosts=(${${${${(f)"$(<$HOME/.ssh/known_hosts)"}:#[\|]*}%%\ *}%%,*}) || _ssh_hosts=()
[[ -r /etc/hosts ]] && : ${(A)_etc_hosts:=${(s: :)${(ps:\t:)${${(f)~~"$(</etc/hosts)"}%%\#*}##[:blank:]#[^[:blank:]]#}}} || _etc_hosts=()
hosts=(
    $(hostname)
    "$_ssh_config_hosts[@]"
    "$_ssh_hosts[@]"
    "$_etc_hosts[@]"
    localhost
)
zstyle ':completion:*:hosts' hosts $hosts

# use generic completion system for programs not yet defined; (_gnu_generic works
# with commands that provide a --help option with "standard" gnu-like output.)
for compcom in cp deborphan df feh fetchipac gpasswd head hnb ipacsum mv \
               pal stow uname ; do
    [[ -z ${_comps[$compcom]} ]] && compdef _gnu_generic ${compcom}
done; unset compcom
