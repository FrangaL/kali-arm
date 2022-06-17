#!/usr/bin/env python3
# REF: https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-devices/-/blob/52cbfb36/scripts/generate_images_stats.py
import yaml # python3 -m pip install pyyaml --user
from datetime import datetime
import sys

OUTPUT_FILE = './md/image-stats.md'
INPUT_FILE = './devices.yml'
repo_msg = "\n_This table was generated automatically on {} from the [Kali ARM GitLab repository](https://gitlab.com/kalilinux/build-scripts/kali-arm)_\n".format(datetime.now().strftime("%Y-%B-%d %H:%M:%S"))
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
    global qty_images
    devices = []
    default = ""

    # Iterate over per input (depth 1)
    for yaml in data['devices']:
        # Iterate over manufactures
        for manufacture in yaml.keys():
            # Iterate over board (depth 2)
            for board in yaml[manufacture]:
                # Iterate over per board
                for key in board.keys():
                    # Check if there is an image for the board
                    if 'images' in key:
                        # Iterate over image (depth 3)
                        for image in board[key]:
                            qty_images += 1
                            devices.append(image.get('name', default))

    table  = "| Display Name |\n"
    table += "|--------------|\n"
    # iterate over all the devices
    for device in sorted(devices):
        table += "| {} |\n".format(device)
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
            meta += 'title: Kali ARM Image Statistics\n'
            meta += '---\n\n'
            stats = "- The next release cycle will include **{}** [Kali ARM images](arm-images.html)\n\n".format(str(qty_images))
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
    print('Images : {}'.format(qty_images))

    exit(0)

if __name__ == "__main__":
    main(sys.argv[1:])
