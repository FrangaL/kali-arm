#!/usr/bin/env python3
# REF: https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-devices/-/blob/951738bb/scripts/generate_kernels_stats.py
import os
from datetime import datetime
import sys

OUTPUT_FILE = './md/kernel-stats.md'
rootdir = './'
repo_msg = "\n_This table was generated automatically on {} from the [Kali ARM GitLab repository](https://gitlab.com/kalilinux/build-scripts/kali-arm)_\n".format(datetime.now().strftime("%Y-%B-%d %H:%M:%S"))
total = 0
qty_versions = {
                'kitkat':      0,
                'lollipop':    0,
                'marshmallow': 0,
                'nougat':      0,
                'oreo':        0,
                'pie':         0,
                'ten':         0,
                'eleven':      0
}

def dcount(path):
    root, dirs, files = next(os.walk(path))
    return len(dirs)

def calc_total():
    t = 0
    for v in qty_versions:
        t += qty_versions[v]
    return t

def generate_table():
    global total
    table  = "| Android Version | Qty |\n"
    table += "|-----------------|-----|\n"
    # iterate over all the devices
    for v in qty_versions:
        table += "| {} | {} |\n".format(v.capitalize(),
                                        str(qty_versions[v]))
    return table

def get_versions():
    for v in qty_versions:
        path = rootdir + v
        qty_versions[v] = dcount(path)

def write_markdown():
    global total
    with open(OUTPUT_FILE, 'w') as f:
        meta  = '---\n'
        meta += 'title: Kali NetHunter Kernel Statistics\n'
        meta += '---\n\n'
        stats = "- The Kali NetHunter repository contains a total of [**{}** kernels](nethunter-kernels.html)\n\n".format(str(total))
        f.write(str(meta))
        f.write(str(stats))
        f.write(str(generated_markdown))
        f.write(str(repo_msg))
        f.close()

def print_text():
    global total
    #print("\nKali NetHunter Kernel Statistics\n")
    #for v in qty_versions:
    #    if len(v) < 8:
    #        tabs = "\t\t"
    #    else:
    #        tabs = "\t"
    #    print(v.capitalize() + ":" + tabs + str(qty_versions[v]))
    #
    #print("=====================================")
    #print("TOTAL:\t\t" + str(total) + "\n")
    print('File: {} successfully written'.format(OUTPUT_FILE))
    print('Kernels: {}'.format(total))

get_versions()
total = calc_total()
generated_markdown = generate_table()
write_markdown()
print_text()
