#! /usr/bin/python3
import sys
import os
from scapy.all import sr1,IP,TCP,ICMP,UDP
#from scapy import *

#conf.checkIPsrc = 0
max_ttl=16

if len(sys.argv) != 2:
    sys.exit('Usage: traceroute.py <remote host>')

# we start with 1
ttl = 1
while ttl < max_ttl :
    #p=sr1(IP(dst=sys.argv[1],ttl=ttl)/ICMP(id=os.getpid()),verbose=0,timeout=3)       # ICMP traceroute (Windows)
    #p=sr1(IP(dst=sys.argv[1],ttl=ttl)/UDP(dport=53),verbose=0,timeout=3)              # UDP traceroute (Unix VJ)
    #p=sr1(IP(dst=sys.argv[1],ttl=ttl)/TCP(dport=80,flags="S"),verbose=0,timeout=3)    # TCPtraceroute
    p=sr1(IP(dst=sys.argv[1],ttl=ttl)/TCP(dport=80,flags="S",options=[('Timestamp',(0,0)),('SAckOK','')]),verbose=0,timeout=3)
    # if time exceeded due to TTL exceeded
    try:
        # Check for ICMP type 11 (time-exceeded)
        if p[ICMP].type == 11 and p[ICMP].code == 0:
            print(ttl, '->', p.src)
            print(p.summary())
            ttl += 1
        elif p[ICMP].type == 0:
            print(ttl, '->', p.src)
            print(p.summary())
            break
    except TypeError as ex:
        print(ttl, '-> timeout')
        ttl += 1
    except IndexError as ex:
        print(ttl, '-> IndexError', ex)
        print(p.summary())
        #print(p.display())
        ttl += 1
        #break
