# record terminal sessions
script(){
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
