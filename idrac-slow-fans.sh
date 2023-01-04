# https://www.reddit.com/r/homelab/comments/7xqb11/dell_fan_noise_control_silence_your_poweredge/
ipmi_addr=${1:-192.168.193.158}
ipmi_user=Administrator
ipmi_password_file=~/ipmi-password.txt

# print temps and fans rpms
#ipmitool -I lanplus -H $ipmi_addr -U $ipmi_user -f $ipmi_password_file sensor reading "Ambient Temp" "FAN 1 RPM" "FAN 2 RPM" "FAN 3 RPM"
# print fan info
#ipmitool -I lanplus -H $ipmi_addr -U $ipmi_user -f $ipmi_password_file sdr get "FAN 1 RPM" "FAN 2 RPM" "FAN 3 RPM"

# enable manual/static fan control
ipmitool -I lanplus -H $ipmi_addr -U $ipmi_user -f $ipmi_password_file raw 0x30 0x30 0x01 0x00
# set fan speed to 18%
fan_percentage=18
fan_percentage_hex=$(printf "0x%x" $fan_percentage)
ipmitool -I lanplus -H $ipmi_addr -U $ipmi_user -f $ipmi_password_file raw 0x30 0x30 0x02 0xff $fan_percentage_hex

#disable manual/static fan control
#ipmitool -I lanplus -H $ipmi_addr -U $ipmi_user -f $ipmi_password_file raw 0x30 0x30 0x01 0x01
