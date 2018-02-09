# Eternal bash history. http://stackoverflow.com/questions/9457233/unlimited-bash-history
# ---------------------
# Undocumented feature which sets the size to "unlimited".
# http://stackoverflow.com/questions/9457233/unlimited-bash-history
export HISTFILESIZE=
export HISTSIZE=
export HISTTIMEFORMAT="[%F %T] "
# Change the file location because certain bash sessions truncate .bash_history file upon close.
# http://superuser.com/questions/575479/bash-history-truncated-to-500-lines-on-each-login
export HISTFILE=~/.bash_eternal_history
# Force prompt to write history after every command.
# http://superuser.com/questions/20900/bash-history-loss
PROMPT_COMMAND="history -a; $PROMPT_COMMAND"
HISTCONTROL=erasedups


# record terminal sessions. Usage example: script mysql-instalation-recording
script_record(){
    # Use first parameter as file suffix, or $USER if there are no params
    local name_suffix=${1:-$USER}
    local script_dir=$HOME/script
    if [ ! -d $script_dir ];then
        mkdir $script_dir || return 1
    fi
    chmod g=,o= $script_dir
    local filename_base=$script_dir/$HOSTNAME-$(date +%F_%H%M%S)-$name_suffix
    /usr/bin/script -t$filename_base.timings $filename_base.script
    echo "Replay: scriptreplay -m 1 -t$filename_base.timings $filename_base.script"
}
