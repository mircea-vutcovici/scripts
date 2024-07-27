#! /usr/bin/python

# For more details: https://www.kernel.org/doc/Documentation/blockdev/zram.txt
import glob

zram_devs=glob.glob('/sys/block/zram*')
for zram_dev in zram_devs:
    with open('{0}/mm_stat'.format(zram_dev), 'r') as mm_stat_fd:
        mm_stat_line=mm_stat_fd.read()
        #print(mm_stat_line)
        #print(mm_stat_line.split())
        orig_data_size,compr_data_size,mem_used_total,mem_limit,mem_used_max,same_pages,pages_compacted,huge_pages,huge_pages_since=[int(x) for x in mm_stat_line.split()]
        print('{0}: original {1} compressed {2} original {3:.0f}KiB compressed {4:.0f}KiB ratio {5:3.2f}% {6:5.2f}x hp {7} hp_since {8}'.format(
            zram_dev, orig_data_size, compr_data_size, orig_data_size/1024, compr_data_size/1024,
            100.0*compr_data_size/orig_data_size, 1.0* orig_data_size/compr_data_size, huge_pages, huge_pages_since))
