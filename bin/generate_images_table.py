#!/usr/bin/env python3
# REF: https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-devices/-/blob/95ad7d2b/scripts/generate_images_table.py
import yaml # python3 -m pip install pyyaml --user
from datetime import datetime
import sys

OUTPUT_FILE = './images.md'
INPUT_FILE = './devices.yml'
repo_msg = "\n_This table was generated automatically on {} from the [Kali ARM GitLab repository](https://gitlab.com/kalilinux/build-scripts/kali-arm)_\n".format(datetime.now().strftime("%Y-%B-%d %H:%M:%S"))
qty_devices = 0
qty_images = 0

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

def generate_device_table(data):
    global qty_devices
    global qty_images
    default = ""
    table  = "| Display Name | Device | Kernel ID | Android Version | Rootfs | Status | Documentation Link | Notes |\n"
    table += "|--------------|--------|-----------|-----------------|--------|--------|--------------------|-------|\n"

    # Iterate over per input (depth 1)
    for yaml in data['devices']:
        # Iterate over manufactures
        for manufacture in yaml.keys():
            # Iterate over board (depth 2)
            for board in yaml[manufacture]:
                qty_devices += 1
                # Iterate over per board
                for key in board.keys():
                    # Check if there is an image for the board
                    if 'images' in key:
                        # Iterate over image (depth 3)
                        for image in board[key]:
                            qty_images += 1
                            table += "| {} | {} | {} | {} | {} | {} | {} | {} |\n".format(image.get('name', default),
                                                                                          key,
                                                                                          image.get('id', default),
                                                                                          image.get('os', default),
                                                                                          image.get('rootfs', default),
                                                                                          image.get('status', default),
                                                                                          image.get('doco', default),
                                                                                          image.get('note', default))
    return table

def readfile(file):
    try:
        with open(file) as f:
            data = f.read()
            f.close()
    except Exception as e:
        print("[-] Cannot open input file: {} - {}".format(file, e))

    return data

def writefile(data, file):
    global repo_msg
    try:
        with open(file, 'w') as f:
            meta  = '---\n'
            meta += 'title: Official Kali ARM Images\n'
            meta += '---\n\n'
            stats  = "- The Kali ARM repository contains kernels for [**{}** devices](arm-image-stats.html)\n".format(str(qty_devices))
            stats += "- The next release cycle will include **{}** [Kali ARM images](https://www.kali.org/get-kali/)\n\n".format(str(qty_images))
            f.write(str(meta))
            f.write(str(stats))
            f.write(str(data))
            f.write(str(repo_msg))
            f.close()
            print('File: {} successfully written'.format(OUTPUT_FILE))
    except Exception as e:
        print("[-] Cannot write to output file: {} - {}".format(file, e))
    return 0

def main(argv):
    # Assign variables
    data = readfile(INPUT_FILE)

    # Get data
    res = yaml_parse(data)
    generated_markdown = generate_device_table(res)

    # Create markdown file
    writefile(generated_markdown, OUTPUT_FILE)

    # Print result and exit
    print('Devices: {}'.format(qty_devices))
    print('Images : {}'.format(qty_images))

    exit(0)

if __name__ == "__main__":
    main(sys.argv[1:])

