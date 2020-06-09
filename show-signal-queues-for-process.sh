#read -p "PID=" pid
pid=$1
cat /proc/$pid/status|egrep '(Sig|Shd)(Pnd|Blk|Ign|Cgt)'|while read name mask;do
    bin=$(echo "ibase=16; obase=2; ${mask^^*}"|bc)
    echo -n "$name $mask $bin "
    i=1
    while [[ $bin -ne 0 ]];do
        if [[ ${bin:(-1)} -eq 1 ]];then
            kill -l $i | tr '\n' ' '
        fi
        bin=${bin::-1}
        set $((i++))
    done
    echo
done
# vim:et:sw=4:ts=4:sts=4:
