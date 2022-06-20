#!/usr/bin/env python3
# REF: https://www.kali.org/docs/arm/
import yaml # python3 -m pip install pyyaml --user
from datetime import datetime
import sys

OUTPUT_FILE = './image-overview.md'
INPUT_FILE = './devices.yml'
repo_msg = "\n_This table was generated automatically on {} from the [Kali ARM GitLab repository](https://gitlab.com/kalilinux/build-scripts/kali-arm)_\n".format(datetime.now().strftime("%Y-%B-%d %H:%M:%S"))
qty_devices = 0
qty_images = 0
qty_image_kali = 0
qty_image_community = 0
qty_image_eol = 0
qty_image_unknown = 0

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
    global qty_devices, qty_images, qty_image_kali, qty_image_community, qty_image_eol, qty_image_unknown
    images = []
    default = ""
    table  = "| [Device](https://www.kali.org/docs/arm/) | [Build-Script](https://gitlab.com/kalilinux/build-scripts/kali-arm/) | [Official Image](https://www.kali.org/get-kali/#kali-arm) | Community Image | Retired Image |\n"
    table += "|--------|--------------|----------------|-----------------|---------------|\n"

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
                            if image['name'] not in images:
                                images.append(image['name']) # ALT: images.append(image['image'])
                                qty_images += 1
                                build_script = image.get('build-script', default)
                                if build_script:
                                    build_script = "[{0}](https://gitlab.com/kalilinux/build-scripts/kali-arm/-/blob/master/{0})".format(build_script)
                                name = image.get('name', default)
                                slug = image.get('slug', default)
                                if name and slug:
                                    name = "[{}](https://www.kali.org/docs/arm/{}/)".format(name, slug)
                                support = image.get('support', default)
                                if support == "kali":
                                    status = "x |  | "
                                    qty_image_kali += 1
                                elif support == "community":
                                    status = " | x | "
                                    qty_image_community += 1
                                elif support == "eol":
                                    status = " |  | x"
                                    qty_image_eol += 1
                                else:
                                    status = " |  | "
                                    qty_image_unknown += 1
                                table += "| {} | {} | {} |\n".format(name,
                                                                     build_script,
                                                                     status)
                            #else:
                            #    print('DUP {} / {}'.format(image['name'], image['image']))
                if 'images' not in board.keys():
                    print("[i] Possible issue with: " + board.get('board', default) + " (no images)")
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
            meta += 'title: Kali ARM Image Overview\n'
            meta += '---\n\n'
            stats  = "- The official [Kali ARM repository](https://gitlab.com/kalilinux/build-scripts/kali-arm) contains build-scripts to create [**{}** unique Kali ARM images](image-stats.html) for **{}** devices\n".format(str(qty_images), str(qty_devices))
            stats += "- The [next release](https://www.kali.org/releases/) cycle will include [**{}** Kali ARM images](image-stats.html) _([ready to download](https://www.kali.org/get-kali/#kali-arm))_, **{}** images which can be built, and {} retired images\n".format(str(qty_image_kali), str(qty_image_community), str(qty_image_eol))
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
    print('Devices: {}'.format(qty_devices))
    print('Images : {}'.format(qty_images))
    print('- Kali     : {}'.format(qty_image_kali))
    print('- Community: {}'.format(qty_image_community))
    print('- EOL      : {}'.format(qty_image_eol))
    print('- Unknown  : {}'.format(qty_image_unknown))
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
