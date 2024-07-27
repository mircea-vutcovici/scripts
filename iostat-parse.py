#! /usr/bin/python3
# sudo dnf install python3-lark
import logging
from lark import Lark, logger

logger.setLevel(logging.WARN)

grammar=r"""
        start: _NL header _NL record+
        header: /Linux .*/

        record: timestamp _NL cpustats _NL diskstats
        timestamp: /[0-9]{4}.*/
        cpustats: cpustatsheader _NL cpustatsvalues
        cpustatsheader: /avg-cpu.*/
        cpustatsvalues: /[0-9].*/

        diskstats: diskstats_header _NL eachdiskstat+
        diskstats_header: /Device.*/
        eachdiskstat: DISKSTATENTRY _NL
        DISKSTATENTRY: /[a-z].*/

        %import common.NEWLINE -> _NL
        %import common.WS_INLINE
        %ignore WS_INLINE
    """

parser = Lark(grammar, parser="lalr")
#parser = Lark(grammar)

# iostat -c -d -x -t -m 1
sample_conf = """
Linux 6.9.8-200.fc40.x86_64 (laptop-rh.vutcovici.ro) 	2024-07-27 	_x86_64_	(4 CPU)

2024-07-27 01:28:22 AM
avg-cpu:  %user   %nice %system %iowait  %steal   %idle
          18.37    0.02    6.64    0.54    0.00   74.42

Device            r/s     rMB/s   rrqm/s  %rrqm r_await rareq-sz     w/s     wMB/s   wrqm/s  %wrqm w_await wareq-sz     d/s     dMB/s   drqm/s  %drqm d_await dareq-sz     f/s f_await  aqu-sz  %util
dm-0             3.94      0.24     0.00   0.00    0.37    62.88   26.29      0.62     0.00   0.00    2.27    24.15    5.11      2.80     0.00   0.00    0.67   562.01    0.00    0.00    0.06   1.48
nvme0n1          4.04      0.24     0.06   1.39    0.30    61.29   24.49      0.62     1.80   6.85    1.16    25.93    5.11      2.80     0.00   0.00    1.01   562.32    1.18    1.03    0.04   1.32
zram0            1.70      0.01     0.00   0.00    0.00     4.00    3.25      0.01     0.00   0.00    0.01     4.00    0.00      0.00     0.00   0.00    0.00     0.00    0.00    0.00    0.00   0.00


2024-07-27 01:28:23 AM
avg-cpu:  %user   %nice %system %iowait  %steal   %idle
          16.28    0.00    6.11    0.00    0.00   77.61

Device            r/s     rMB/s   rrqm/s  %rrqm r_await rareq-sz     w/s     wMB/s   wrqm/s  %wrqm w_await wareq-sz     d/s     dMB/s   drqm/s  %drqm d_await dareq-sz     f/s f_await  aqu-sz  %util
dm-0             0.00      0.00     0.00   0.00    0.00     0.00    0.00      0.00     0.00   0.00    0.00     0.00    0.00      0.00     0.00   0.00    0.00     0.00    0.00    0.00    0.00   0.00
nvme0n1          0.00      0.00     0.00   0.00    0.00     0.00    0.00      0.00     0.00   0.00    0.00     0.00    0.00      0.00     0.00   0.00    0.00     0.00    0.00    0.00    0.00   0.00
zram0            0.00      0.00     0.00   0.00    0.00     0.00    0.00      0.00     0.00   0.00    0.00     0.00    0.00      0.00     0.00   0.00    0.00     0.00    0.00    0.00    0.00   0.00
"""

print(parser.parse(sample_conf).pretty())
