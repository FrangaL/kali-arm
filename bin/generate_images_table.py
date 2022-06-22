#!/usr/bin/env python3
# REF: https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-devices/-/blob/95ad7d2b/scripts/generate_images_table.py
import yaml # python3 -m pip install pyyaml --user
from datetime import datetime
import sys

OUTPUT_FILE = './images.md'
INPUT_FILE = './devices.yml'
repo_msg = "\n_This table was [generated automatically](https://gitlab.com/kalilinux/build-scripts/kali-arm/-/blob/master/devices.yml) on {} from the [Kali ARM GitLab repository](https://gitlab.com/kalilinux/build-scripts/kali-arm)_\n".format(datetime.now().strftime("%Y-%B-%d %H:%M:%S"))
qty_devices = 0
qty_images = 0
qty_images_released = 0

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
    global qty_devices, qty_images, qty_images_released
    images = []
    images_released = []
    default = ""
    table  = "| Image Name | Filename | Architecture | Preferred | Support | [Documentation](https://www.kali.org/docs/arm/) | [Kernel](kernel.html) | Kernel Version | Notes |\n"
    table += "|------------|----------|--------------|-----------|---------|-------------------------------------------------|-----------------------|----------------|-------|\n"

    # Iterate over per input (depth 1)
    for yaml in data['devices']:
        # Iterate over vendors
        for vendor in yaml.keys():
            # Iterate over board (depth 2)
            for board in yaml[vendor]:
                qty_devices += 1
                # Iterate over per board
                for key in board.keys():
                    # Check if there is an image for the board
                    if 'images' in key:
                        # Iterate over image (depth 3)
                        for image in board[key]:
                            #qty_images += 1
                            images.append("{}".format(image.get('name', default)))
                            support = image.get('support', default)
                            if support == "kali":
                                #qty_images_released += 1
                                images_released.append("{}".format(image.get('name', default)))
                            slug = image.get('slug', default)
                            if slug:
                                slug = "[{0}](https://www.kali.org/docs/arm/{0}/)".format(slug)
                            table += "| {} | {} | {} | {} | {} | {} | {} | {} |\n".format(image.get('name', default),
                                                                                          image.get('image', default),
                                                                                          image.get('architecture', default),
                                                                                          image.get('recommended', default),
                                                                                          image.get('support', default),
                                                                                          slug,
                                                                                          image.get('kernel', default),
                                                                                          image.get('kernel-version', default),
                                                                                          image.get('image-notes', default))
                if 'images' not in board.keys():
                    print("[i] Possible issue with: " + board.get('board', default) + " (no images)")
    qty_images = len(set(images))
    qty_images_released = len(set(images_released))
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
            meta += 'title: Kali ARM Images\n'
            meta += '---\n\n'
            stats  = "- The official [Kali ARM repository](https://gitlab.com/kalilinux/build-scripts/kali-arm) contains [build-scripts]((https://gitlab.com/kalilinux/build-scripts/kali-arm)) to create [**{}** unique Kali ARM images](image-stats.html) for **{}** devices\n".format(str(qty_images), str(qty_devices))
            stats += "- The [next release](https://www.kali.org/releases/) cycle will include [**{}** Kali ARM images](image-stats.html) _([ready to download](https://www.kali.org/get-kali/#kali-arm))_\n".format(str(qty_images_released))
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
    print('Devices        : {}'.format(qty_devices))
    print('Images         : {}'.format(qty_images))
    print('Images Released: {}'.format(qty_images_released))

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
