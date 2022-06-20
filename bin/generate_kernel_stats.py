#!/usr/bin/env python3
# REF: https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-devices/-/blob/52cbfb36/scripts/generate_images_stats.py
import yaml # python3 -m pip install pyyaml --user
from datetime import datetime
import sys

OUTPUT_FILE = './kernel-stats.md'
INPUT_FILE = './devices.yml'
repo_msg = "\n_This table was generated automatically on {} from the [Kali ARM GitLab repository](https://gitlab.com/kalilinux/build-scripts/kali-arm)_\n".format(datetime.now().strftime("%Y-%B-%d %H:%M:%S"))
qty_kernels = 0
qty_versions = {
                'custom':  0,
                'kali':    0,
                'vendor':  0,
                'unknown': 0
               }

## Input:
## ------------------------------------------------------------ ##
## See: ./devices.yml
##      https://gitlab.com/kalilinux/build-scripts/kali-arm/-/blob/master/devices.yml

def yaml_parse(content):
    result = ""
    lines = content.split('\n')
    for line in lines:
        if line.strip() and not line.strip().startswith('#'):
            result += line + "\n"
    return yaml.safe_load(result)

def generate_table(data):
    global qty_kernels, qty_versions
    images = []
    default = "unknown"

    # Iterate over per input (depth 1)
    for yaml in data['devices']:
        # Iterate over vendors
        for vendor in yaml.keys():
            # Iterate over board (depth 2)
            for board in yaml[vendor]:
                # Iterate over per board
                for key in board.keys():
                    # Check if there is an image for the board
                    if 'images' in key:
                        # Iterate over image (depth 3)
                        for image in board[key]:
                            if image['name'] not in images:
                                images.append(image['name']) # ALT: images.append(image['image'])
                                qty_kernels += 1
                                qty_versions[(image.get('kernel', default))] += 1
                            #else:
                            #    print('DUP {} / {}'.format(image['name'], image['image']))
                if 'images' not in board.keys():
                    print("[i] Possible issue with: " + board.get('board', default) + " (no images)")

    table  = "| Kernel | Qty |\n"
    table += "|--------|-----|\n"

    # iterate over all the devices
    for v in qty_versions:
        table += "| {} | {} |\n".format(v.capitalize(),
                                        str(qty_versions[v]))
    return table

def read_file(file):
    try:
        with open(file) as f:
            data = f.read()
            f.close()
    except Exception as e:
        print("[-] Cannot open input file: {} - {}".format(file, e))
    return data

def write_file(data, file):
    try:
        with open(file, 'w') as f:
            meta  = '---\n'
            meta += 'title: Kali ARM Kernel Statistics\n'
            meta += '---\n\n'
            stats  = "- The official [Kali ARM repository](https://gitlab.com/kalilinux/build-scripts/kali-arm) contains build-scripts to create [**{}** unique Kali ARM images](images.html)\n".format(str(qty_kernels))
            stats += "- [Kali ARM Statistics](index.html)\n\n"
            f.write(str(meta))
            f.write(str(stats))
            f.write(str(data))
            f.write(str(repo_msg))
            f.close()
            print('[+] File: {} successfully written'.format(OUTPUT_FILE))
    except Exception as e:
        print("[-] Cannot write to output file: {} - {}".format(file, e))
    return 0

def print_summary():
    print('Kernels: {}'.format(qty_kernels))

def main(argv):
    # Assign variables
    data = read_file(INPUT_FILE)

    # Get data
    res = yaml_parse(data)
    generated_markdown = generate_table(res)

    # Create markdown file
    write_file(generated_markdown, OUTPUT_FILE)

    # Print result
    print_summary()

    # Exit
    exit(0)

if __name__ == "__main__":
    main(sys.argv[1:])
