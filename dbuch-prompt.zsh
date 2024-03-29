# For my own and others sanity
# git:
# %b => current branch
# %a => current action (rebase/merge)
# prompt:
# %F => color dict
# %f => reset color
# %~ => current path
# %* => time
# %n => username
# %m => shortname host
# %(?..) => prompt conditional - %(condition.true.false)
# terminal codes:
# \e7   => save cursor position
# \e[2A => move cursor 2 lines up
# \e[1G => go to position 1 in terminal
# \e8   => restore cursor position
# \e[K  => clears everything after the cursor on the current line
# \e[2K => clear everything on the current line
#

autoload -U async && async

# Turns seconds into human readable time.
# 165392 => 1d 21h 56m 32s
# https://github.com/sindresorhus/pretty-time-zsh
prompt_dbuch_human_time_to_var() {
  local human total_seconds=$1 var=$2
  local days=$(( total_seconds / 60 / 60 / 24 ))
  local hours=$(( total_seconds / 60 / 60 % 24 ))
  local minutes=$(( total_seconds / 60 % 60 ))
  local seconds=$(( total_seconds % 60 ))
  (( days > 0 )) && human+="${days}d "
  (( hours > 0 )) && human+="${hours}h "
  (( minutes > 0 )) && human+="${minutes}m "
  human+="${seconds}s"

  # Store human readable time in a variable as specified by the caller
  typeset -g "${var}"="${human}"
}

# Stores (into prompt_dbuch_cmd_exec_time) the execution
# time of the last command if set threshold was exceeded.
prompt_dbuch_check_cmd_exec_time() {
  integer elapsed
  (( elapsed = EPOCHSECONDS - ${prompt_dbuch_cmd_timestamp:-$EPOCHSECONDS} ))
  typeset -g prompt_dbuch_cmd_exec_time=
  (( elapsed > ${DBUCH_CMD_MAX_EXEC_TIME:-5} )) && {
    prompt_dbuch_human_time_to_var $elapsed "prompt_dbuch_cmd_exec_time"
  }
}

prompt_dbuch_set_title() {
  setopt localoptions noshwordsplit

  # Emacs terminal does not support settings the title.
  (( ${+EMACS} )) && return

  case $TTY in
    # Don't set title over serial console.
    /dev/ttyS[0-9]*) return;;
  esac

  # Show hostname if connected via SSH.
  local hostname=
  if [[ -n $prompt_dbuch_state[username] ]]; then
    # Expand in-place in case ignore-escape is used.
    hostname="${(%):-(%m) }"
  fi

  local -a opts
  case $1 in
    expand-prompt) opts=(-P);;
    ignore-escape) opts=(-r);;
  esac

  # Set title atomically in one print statement so that it works when XTRACE is enabled.
  print -n $opts $'\e]0;'${hostname}${2}$'\a'
}

prompt_dbuch_preexec() {
  if [[ -n $prompt_dbuch_git_fetch_pattern ]]; then
    # Detect when Git is performing pull/fetch, including Git aliases.
    local -H MATCH MBEGIN MEND match mbegin mend
    if [[ $2 =~ (git|hub)\ (.*\ )?($prompt_dbuch_git_fetch_pattern)(\ .*)?$ ]]; then
      # We must flush the async jobs to cancel our git fetch in order
      # to avoid conflicts with the user issued pull / fetch.
      async_flush_jobs 'prompt_dbuch'
    fi
  fi

  typeset -g prompt_dbuch_cmd_timestamp=$EPOCHSECONDS

  # Shows the current directory and executed command in the title while a process is active.
  prompt_dbuch_set_title 'ignore-escape' "$PWD:t: $2"

  # Disallow Python virtualenv from updating the prompt. Set it to 12 if
  # untouched by the user to indicate that dbuch modified it. Here we use
  # the magic number 12, same as in `psvar`.
  export VIRTUAL_ENV_DISABLE_PROMPT=${VIRTUAL_ENV_DISABLE_PROMPT:-12}
}

# Change the colors if their value are different from the current ones.
prompt_dbuch_set_colors() {
  local color_temp key value
  for key value in ${(kv)prompt_dbuch_colors}; do
    zstyle -t ":prompt:dbuch:$key" color "$value"
    case $? in
      1) # The current style is different from the one from zstyle.
        zstyle -s ":prompt:dbuch:$key" color color_temp
        prompt_dbuch_colors[$key]=$color_temp ;;
      2) # No style is defined.
        prompt_dbuch_colors[$key]=$prompt_dbuch_colors_default[$key] ;;
    esac
  done
}

prompt_dbuch_precmd() {
  # Check execution time and store it in a variable.
  prompt_dbuch_check_cmd_exec_time
  unset prompt_dbuch_cmd_timestamp

  # Shows the full path in the title.
  prompt_dbuch_set_title 'expand-prompt' '%~'

  # Modify the colors if some have changed..
  prompt_dbuch_set_colors

  # Perform async Git dirty check and fetch.
  prompt_dbuch_async_tasks

  # Check if we should display the virtual env. We use a sufficiently high
  # index of psvar (12) here to avoid collisions with user defined entries.
  psvar[12]=
  # When VIRTUAL_ENV_DISABLE_PROMPT is empty, it was unset by the user and
  # dbuch should take back control.
  if [[ -n $VIRTUAL_ENV ]] && [[ -z $VIRTUAL_ENV_DISABLE_PROMPT || $VIRTUAL_ENV_DISABLE_PROMPT = 12 ]]; then
    psvar[12]="${VIRTUAL_ENV:t}"
    export VIRTUAL_ENV_DISABLE_PROMPT=12
  fi

  # Make sure VIM prompt is reset.
  prompt_dbuch_reset_prompt_symbol

  # Print the preprompt.
  prompt_dbuch_prompt_render "precmd"
}

prompt_dbuch_async_git_aliases() {
  setopt localoptions noshwordsplit
  local -a gitalias pullalias

  # List all aliases and split on newline.
  gitalias=(${(@f)"$(command git config --get-regexp "^alias\.")"})
  for line in $gitalias; do
    parts=(${(@)=line})           # Split line on spaces.
      aliasname=${parts[1]#alias.}  # Grab the name (alias.[name]).
      shift parts                   # Remove `aliasname`

    # Check alias for pull or fetch. Must be exact match.
    if [[ $parts =~ ^(.*\ )?(pull|fetch)(\ .*)?$ ]]; then
      pullalias+=($aliasname)
    fi
  done

  print -- ${(j:|:)pullalias}  # Join on pipe, for use in regex.
}

prompt_dbuch_async_vcs_info() {
  setopt localoptions noshwordsplit

  # Configure `vcs_info` inside an async task. This frees up `vcs_info`
  # to be used or configured as the user pleases.
  zstyle ':vcs_info:*' enable git
  zstyle ':vcs_info:*' use-simple true
  # Only export three message variables from `vcs_info`.
  zstyle ':vcs_info:*' max-exports 3
  # Export branch (%b), Git toplevel (%R), and action (rebase/cherry-pick) (%a).
  zstyle ':vcs_info:git*' formats '%b' '%R'
  zstyle ':vcs_info:git*' actionformats '%b' '%R' '%a'

  vcs_info

  local -A info
  info[pwd]=$PWD
  info[top]=$vcs_info_msg_1_
  info[branch]=$vcs_info_msg_0_
  info[action]=$vcs_info_msg_2_

  print -r - ${(@kvq)info}
}

# Fastest possible way to check if a Git repo is dirty.
prompt_dbuch_async_git_dirty() {
  setopt localoptions noshwordsplit
  local untracked_dirty=$1

  if [[ $untracked_dirty = 0 ]]; then
    command git diff --no-ext-diff --quiet --exit-code
  else
    test -z "$(command git status --porcelain --ignore-submodules -unormal)"
  fi

  return $?
}

prompt_dbuch_async_git_fetch() {
  setopt localoptions noshwordsplit

  # Sets `GIT_TERMINAL_PROMPT=0` to disable authentication prompt for Git fetch (Git 2.3+).
  export GIT_TERMINAL_PROMPT=0
  # Set SSH `BachMode` to disable all interactive SSH password prompting.
  export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-"ssh"} -o BatchMode=yes"

  # Default return code, which indicates Git fetch failure.
  local fail_code=99

  # Guard against all forms of password prompts. By setting the shell into
  # MONITOR mode we can notice when a child process prompts for user input
  # because it will be suspended. Since we are inside an async worker, we
  # have no way of transmitting the password and the only option is to
  # kill it. If we don't do it this way, the process will corrupt with the
  # async worker.
  setopt localtraps monitor

  # Make sure local HUP trap is unset to allow for signal propagation when
  # the async worker is flushed.
  trap - HUP

  trap '
  # Unset trap to prevent infinite loop
  trap - CHLD
  if [[ $jobstates = suspended* ]]; then
    # Set fail code to password prompt and kill the fetch.
    fail_code=98
    kill %%
  fi
  ' CHLD

  command git -c gc.auto=0 fetch >/dev/null &
  wait $! || return $fail_code

  unsetopt monitor

  # Check arrow status after a successful `git fetch`.
  prompt_dbuch_async_git_arrows
}

prompt_dbuch_async_git_arrows() {
  setopt localoptions noshwordsplit
  command git rev-list --left-right --count HEAD...@'{u}'
}

prompt_dbuch_async_renice() {
  setopt localoptions noshwordsplit
  if command -v renice >/dev/null; then
    command renice +15 -p $$
  fi
  if command -v ionice >/dev/null; then
    command ionice -c 3 -p $$
  fi
}

prompt_dbuch_async_tasks() {
  setopt localoptions noshwordsplit

  # Initialize the async worker.
  ((!${prompt_dbuch_async_init:-0})) && {
    async_start_worker "prompt_dbuch" -u -n
      async_register_callback "prompt_dbuch" prompt_dbuch_async_callback
      typeset -g prompt_dbuch_async_init=1
      async_job "prompt_dbuch" prompt_dbuch_async_renice
    }

  # Update the current working directory of the async worker.
  async_worker_eval "prompt_dbuch" builtin cd -q $PWD

  typeset -gA prompt_dbuch_vcs_info

  local -H MATCH MBEGIN MEND
  if [[ $PWD != ${prompt_dbuch_vcs_info[pwd]}* ]]; then
    # Stop any running async jobs.
    async_flush_jobs "prompt_dbuch"

    # Reset Git preprompt variables, switching working tree.
    unset prompt_dbuch_git_dirty
    unset prompt_dbuch_git_last_dirty_check_timestamp
    unset prompt_dbuch_git_arrows
    unset prompt_dbuch_git_fetch_pattern
    prompt_dbuch_vcs_info[branch]=
    prompt_dbuch_vcs_info[top]=
  fi
  unset MATCH MBEGIN MEND

  async_job "prompt_dbuch" prompt_dbuch_async_vcs_info

  # Only perform tasks inside a Git working tree.
  [[ -n $prompt_dbuch_vcs_info[top] ]] || return

  prompt_dbuch_async_refresh
}

prompt_dbuch_async_refresh() {
  setopt localoptions noshwordsplit

  if [[ -z $prompt_dbuch_git_fetch_pattern ]]; then
    # We set the pattern here to avoid redoing the pattern check until the
    # working three has changed. Pull and fetch are always valid patterns.
    typeset -g prompt_dbuch_git_fetch_pattern="pull|fetch"
    async_job "prompt_dbuch" prompt_dbuch_async_git_aliases
  fi

  async_job "prompt_dbuch" prompt_dbuch_async_git_arrows

  # Do not preform `git fetch` if it is disabled or in home folder.
  if (( ${DBUCH_GIT_PULL:-1} )) && [[ $prompt_dbuch_vcs_info[top] != $HOME ]]; then
    # Tell the async worker to do a `git fetch`.
    async_job "prompt_dbuch" prompt_dbuch_async_git_fetch
  fi

  # If dirty checking is sufficiently fast,
  # tell the worker to check it again, or wait for timeout.
  integer time_since_last_dirty_check=$(( EPOCHSECONDS - ${prompt_dbuch_git_last_dirty_check_timestamp:-0} ))
  if (( time_since_last_dirty_check > ${DBUCH_GIT_DELAY_DIRTY_CHECK:-1800} )); then
    unset prompt_dbuch_git_last_dirty_check_timestamp
    # Check check if there is anything to pull.
    async_job "prompt_dbuch" prompt_dbuch_async_git_dirty ${DBUCH_GIT_UNTRACKED_DIRTY:-1}
  fi
}

prompt_dbuch_check_git_arrows() {
  setopt localoptions noshwordsplit
  local arrows left=${1:-0} right=${2:-0}

  (( right > 0 )) && arrows+=${DBUCH_GIT_DOWN_ARROW:-⇣}
  (( left > 0 )) && arrows+=${DBUCH_GIT_UP_ARROW:-⇡}

  [[ -n $arrows ]] || return
  typeset -g REPLY=$arrows
}

prompt_dbuch_async_callback() {
  setopt localoptions noshwordsplit
  local job=$1 code=$2 output=$3 exec_time=$4 next_pending=$6
  local do_render=0

  case $job in
    \[async])
      # Code is 1 for corrupted worker output and 2 for dead worker.
      if [[ $code -eq 2 ]]; then
        # Our worker died unexpectedly.
        typeset -g prompt_dbuch_async_init=0
      fi
      ;;
    prompt_dbuch_async_vcs_info)
      local -A info
      typeset -gA prompt_dbuch_vcs_info

      # Parse output (z) and unquote as array (Q@).
      info=("${(Q@)${(z)output}}")
      local -H MATCH MBEGIN MEND
      if [[ $info[pwd] != $PWD ]]; then
        # The path has changed since the check started, abort.
        return
      fi
      # Check if Git top-level has changed.
      if [[ $info[top] = $prompt_dbuch_vcs_info[top] ]]; then
        # If the stored pwd is part of $PWD, $PWD is shorter and likelier
        # to be top-level, so we update pwd.
        if [[ $prompt_dbuch_vcs_info[pwd] = ${PWD}* ]]; then
          prompt_dbuch_vcs_info[pwd]=$PWD
        fi
      else
        # Store $PWD to detect if we (maybe) left the Git path.
        prompt_dbuch_vcs_info[pwd]=$PWD
      fi
      unset MATCH MBEGIN MEND

      # The update has a Git top-level set, which means we just entered a new
      # Git directory. Run the async refresh tasks.
      [[ -n $info[top] ]] && [[ -z $prompt_dbuch_vcs_info[top] ]] && prompt_dbuch_async_refresh

      # Always update branch and top-level.
      prompt_dbuch_vcs_info[branch]=$info[branch]
      prompt_dbuch_vcs_info[top]=$info[top]
      prompt_dbuch_vcs_info[action]=$info[action]

      do_render=1
      ;;
    prompt_dbuch_async_git_aliases)
      if [[ -n $output ]]; then
        # Append custom Git aliases to the predefined ones.
        prompt_dbuch_git_fetch_pattern+="|$output"
      fi
      ;;
    prompt_dbuch_async_git_dirty)
      local prev_dirty=$prompt_dbuch_git_dirty
      if (( code == 0 )); then
        unset prompt_dbuch_git_dirty
      else
        typeset -g prompt_dbuch_git_dirty="*"
      fi

      [[ $prev_dirty != $prompt_dbuch_git_dirty ]] && do_render=1

      # When `prompt_dbuch_git_last_dirty_check_timestamp` is set, the Git info is displayed
      # in a different color. To distinguish between a "fresh" and a "cached" result, the
      # preprompt is rendered before setting this variable. Thus, only upon the next
      # rendering of the preprompt will the result appear in a different color.
      (( $exec_time > 5 )) && prompt_dbuch_git_last_dirty_check_timestamp=$EPOCHSECONDS
      ;;
    prompt_dbuch_async_git_fetch|prompt_dbuch_async_git_arrows)
      # `prompt_dbuch_async_git_fetch` executes `prompt_dbuch_async_git_arrows`
      # after a successful fetch.
      case $code in
        0)
          local REPLY
          prompt_dbuch_check_git_arrows ${(ps:\t:)output}
          if [[ $prompt_dbuch_git_arrows != $REPLY ]]; then
            typeset -g prompt_dbuch_git_arrows=$REPLY
            do_render=1
          fi
          ;;
        99|98)
          # Git fetch failed.
          ;;
        *)
          # Non-zero exit status from `prompt_dbuch_async_git_arrows`,
          # indicating that there is no upstream configured.
          if [[ -n $prompt_dbuch_git_arrows ]]; then
            unset prompt_dbuch_git_arrows
            do_render=1
          fi
          ;;
      esac
      ;;
    prompt_dbuch_async_renice)
      ;;
  esac

  if (( next_pending )); then
    (( do_render )) && typeset -g prompt_dbuch_async_render_requested=1
    return
  fi

  [[ ${prompt_dbuch_async_render_requested:-$do_render} = 1 ]] && prompt_dbuch_prompt_render
  unset prompt_dbuch_async_render_requested
}

prompt_dbuch_reset_prompt() {
  if [[ $CONTEXT == cont ]]; then
    # When the context is "cont", PS2 is active and calling
    # reset-prompt will have no effect on PS1, but it will
    # reset the execution context (%_) of PS2 which we don't
    # want. Unfortunately, we can't save the output of "%_"
    # either because it is only ever rendered as part of the
    # prompt, expanding in-place won't work.
    return
  fi

  zle && zle .reset-prompt
}

prompt_dbuch_reset_prompt_symbol() {
  prompt_dbuch_state[prompt]=${DBUCH_PROMPT_SYMBOL:- }
}

prompt_dbuch_update_vim_prompt_widget() {
  setopt localoptions noshwordsplit
  prompt_dbuch_state[prompt]=${${KEYMAP/vicmd/${DBUCH_PROMPT_VICMD_SYMBOL:- }}/(main|viins)/${DBUCH_PROMPT_SYMBOL:- }}

  prompt_dbuch_reset_prompt
}

prompt_dbuch_reset_vim_prompt_widget() {
  setopt localoptions noshwordsplit
  prompt_dbuch_reset_prompt_symbol

  # We can't perform a prompt reset at this point because it
  # removes the prompt marks inserted by macOS Terminal.
}

prompt_dbuch_state_setup() {
  setopt localoptions noshwordsplit

  # Check SSH_CONNECTION and the current state.
  local ssh_connection=${SSH_CONNECTION:-$PROMPT_DBUCH_SSH_CONNECTION}
  local username hostname
  if [[ -z $ssh_connection ]] && (( $+commands[who] )); then
    # When changing user on a remote system, the $SSH_CONNECTION
    # environment variable can be lost. Attempt detection via `who`.
    local who_out
    who_out=$(who -m 2>/dev/null)
    if (( $? )); then
      # Who am I not supported, fallback to plain who.
      local -a who_in
      who_in=( ${(f)"$(who 2>/dev/null)"} )
      who_out="${(M)who_in:#*[[:space:]]${TTY#/dev/}[[:space:]]*}"
    fi

    local reIPv6='(([0-9a-fA-F]+:)|:){2,}[0-9a-fA-F]+'  # Simplified, only checks partial pattern.
    local reIPv4='([0-9]{1,3}\.){3}[0-9]+'   # Simplified, allows invalid ranges.
    # Here we assume two non-consecutive periods represents a
    # hostname. This matches `foo.bar.baz`, but not `foo.bar`.
    local reHostname='([.][^. ]+){2}'

    # Usually the remote address is surrounded by parenthesis, but
    # not on all systems (e.g. busybox).
    local -H MATCH MBEGIN MEND
    if [[ $who_out =~ "\(?($reIPv4|$reIPv6|$reHostname)\)?\$" ]]; then
      ssh_connection=$MATCH

      # Export variable to allow detection propagation inside
      # shells spawned by this one (e.g. tmux does not always
      # inherit the same tty, which breaks detection).
      export PROMPT_DBUCH_SSH_CONNECTION=$ssh_connection
    fi
    unset MATCH MBEGIN MEND
  fi

  # Regular hostname
  hostname='%F{$prompt_dbuch_colors[host]}%m%f'
  
  # Show `username@host` if logged in through SSH.
  [[ -n $ssh_connection ]] && hostname='%F{$prompt_dbuch_colors[host:ssh]}%m%f'
  
  [[ $UID -eq 0 ]] && hostname='%F{$prompt_dbuch_colors[host:root]}%m%f'

  # Show `username@host` if root, with username in default color.
  username='%F{$prompt_dbuch_colors[user:root]}%n%f'

  typeset -gA prompt_dbuch_state
  prompt_dbuch_state[version]="0.1.0"
  prompt_dbuch_state+=(
    username "$username"
    hostname "$hostname"
    prompt	 "${DBUCH_PROMPT_SYMBOL:- }"
  )
}

prompt_dbuch_prompt_render() {
  setopt localoptions noshwordsplit

  # Set color for Git branch/dirty status and change color if dirty checking has been delayed.
  local git_color=$prompt_dbuch_colors[git:branch]
  local git_dirty_color=$prompt_dbuch_colors[git:dirty]
  local surrounded_begin="%F{$prompt_dbuch_colors[surrounded]}[%f"
  local surrounded_end="%F{$prompt_dbuch_colors[surrounded]}]%f"
  [[ -n ${prompt_dbuch_git_last_dirty_check_timestamp+x} ]] && git_color=$prompt_dbuch_colors[git:branch:cached]

  # Initialize the prompt arrays.
  local -a prompt_tokens
  local -a rprompt_tokens

  # Set Machine token
  prompt_tokens+=('$prompt_dbuch_state[hostname]')

  # Set the path.
  prompt_tokens+=('%F{${prompt_dbuch_colors[path]}}%(4~|%-1~/…/%2~/|%~/)%f')

  # Add Git branch and dirty status info.
  typeset -gA prompt_dbuch_vcs_info
  if [[ -n $prompt_dbuch_vcs_info[branch] ]]; then
    local -a git_token
    git_token+=($surrounded_begin)
    local branch="%F{$git_color}"'${prompt_dbuch_vcs_info[branch]}'
    if [[ -n $prompt_dbuch_vcs_info[action] ]]; then
      branch+="|%F{$prompt_dbuch_colors[git:action]}"'$prompt_dbuch_vcs_info[action]'"%F{$git_color}"
    fi

    git_token+=("$branch""%F{$git_dirty_color}"'${prompt_dbuch_git_dirty}%f')
    # Git pull/push arrows.
    if [[ -n $prompt_dbuch_git_arrows ]]; then
      git_token+=('%F{$prompt_dbuch_colors[git:arrow]}${prompt_dbuch_git_arrows}%f')
    fi
    git_token+=($surrounded_end)
    prompt_tokens+=(${(j..)git_token})
  fi

  # add prompt
  prompt_tokens+='${prompt_dbuch_state[prompt]} '

  # Execution time.
  [[ -n $prompt_dbuch_cmd_exec_time ]] && rprompt_tokens+=('%F{white}${prompt_dbuch_cmd_exec_time}%f')
  rprompt_tokens+='%(?..%F{$prompt_dbuch_colors[result:error]}%?%f)'


  local cleaned_ps1=$PROMPT
  local -H MATCH MBEGIN MEND
  # Remove everything from the prompt until the newline. This
  # removes the preprompt and only the original PROMPT remains.
  cleaned_ps1=${PROMPT##*}
  unset MATCH MBEGIN MEND

  # Construct the new prompt with a clean preprompt.
  local -ah ps1
  ps1=(
    ${(j. .)prompt_tokens}  # Join parts, space separated.
    $cleaned_ps1
  )

  PROMPT="${(j..)ps1}"
  RPROMPT="${(j. | .)rprompt_tokens}"

  # Expand the prompt for future comparision.
  local expanded_prompt
  expanded_prompt="${(S%%)PROMPT}"

  if [[ $prompt_dbuch_last_prompt != $expanded_prompt ]]; then
    # Redraw the prompt.
    prompt_dbuch_reset_prompt
  fi

  typeset -g prompt_dbuch_last_prompt=$expanded_prompt
}

prompt_dbuch_setup() {
  # Prevent percentage showing up if output doesn't end with a newline.
  export PROMPT_EOL_MARK=''

  prompt_opts=(subst percent)

  # Borrowed from `promptinit`. Sets the prompt options in case dbuch was not
  # initialized via `promptinit`.
  setopt noprompt{bang,cr,percent,subst} "prompt${^prompt_opts[@]}"

  if [[ -z $prompt_newline ]]; then
    # This variable needs to be set, usually set by promptinit.
    typeset -g prompt_newline=$'\n%{\r%}'
  fi

  zmodload zsh/datetime
  zmodload zsh/zle
  zmodload zsh/parameter
  zmodload zsh/zutil

  autoload -Uz add-zsh-hook
  autoload -Uz vcs_info
  autoload -Uz async && async

  # The `add-zle-hook-widget` function is not guaranteed to be available.
  # It was added in Zsh 5.3.
  autoload -Uz +X add-zle-hook-widget 2>/dev/null

  # Set the colors.
  typeset -gA prompt_dbuch_colors_default prompt_dbuch_colors
  prompt_dbuch_colors_default=(
    git:arrow            cyan
    git:branch           green
    git:branch:cached    red
    git:action           242
    git:dirty            218
    host                 85
    host:ssh             green
    host:root            red
    path                 blue
    result:error         red
    result:success       green
    user                 242
    user:root            red
    surrounded           magenta
  )
  prompt_dbuch_colors=("${(@kv)prompt_dbuch_colors_default}")

  add-zsh-hook precmd prompt_dbuch_precmd
  add-zsh-hook preexec prompt_dbuch_preexec

  prompt_dbuch_state_setup

  zle -N prompt_dbuch_reset_prompt
  zle -N prompt_dbuch_update_vim_prompt_widget
  zle -N prompt_dbuch_reset_vim_prompt_widget
  if (( $+functions[add-zle-hook-widget] )); then
    add-zle-hook-widget zle-line-finish prompt_dbuch_reset_vim_prompt_widget
    add-zle-hook-widget zle-keymap-select prompt_dbuch_update_vim_prompt_widget
  fi
}

prompt_dbuch_setup "$@"
