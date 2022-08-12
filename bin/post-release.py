#!/usr/bin/env python3

## ARM Devices ~ https://gitlab.com/kalilinux/build-scripts/kali-arm/-/blob/master/devices.yml

###############################################
## Script to prepare the rpi-imager json script for Kali ARM quarterly releases.
## Based on ./bin/pre-release.py
##
## This should be run after images are created.
##
## It parses the YAML sections of the devices.yml and creates:
## - "<imagedir>/rpi-imager.json = "manifest file mapping image name to display name
##
## Dependencies:
##   sudo apt -y install python3 python3-yaml xz-utils
##
## Usage:
##  ./bin/post-release.py -i <input file> -r <release> -o <image directory>
##
## E.g.:
## ./bin/post-release.py -i devices.yml -r 2022.3 -o images/

import datetime
import json
import re
import subprocess
import yaml # python3 -m pip install pyyaml --user
import getopt, os, stat, sys

manifest = ""     # Generated automatically (<imagedir>/rpi-imager.json)
release = ""
imagedir = ""
inputfile = ""
qty_devices = 0
qty_images = 0
qty_release_images = 0
file_ext = ['xz', 'xz.sha256sum', 'sha256sum']

## Input:
## ------------------------------------------------------------ ##
## See: ./devices.yml
##      https://gitlab.com/kalilinux/build-scripts/kali-arm/-/blob/master/devices.yml
##
## See: ./images/*.img.sha256sum (uncompressed image sha256sum - to get the sha256sum
##      ./images/*.img.xz.sha256sum (compressed image sha256sum - to get the sha256sum
##      ./images/*.img.xz (compressed image; we use xz to look at the metadata to get compressed/uncompressed size)

def bail(message = "", strerror = ""):
    outstr = ""
    prog = sys.argv[0]
    if message != "":
        outstr = "\nError: {}".format(message)

    if strerror != "":
        outstr += "\nMessage: {}\n".format(strerror)
    else:
        outstr += "\n\nUsage: {} -i <input file> -o <output directory> -r <release>".format(prog)
        outstr += "\nE.g. : {} -i devices.yml -o images/ -r {}.1\n".format(prog, datetime.datetime.now().year)
    print(outstr)
    sys.exit(2)

def getargs(argv):
    global inputfile, imagedir, release

    try:
        opts, args = getopt.getopt(argv,"hi:o:r:",["inputfile=","imagedir=","release="])
    except getopt.GetoptError as e:
        bail("Incorrect arguments: {}".format(e))

    if opts:
        for opt, arg in opts:
            if opt == '-h':
                bail()
            elif opt in ("-i", "--inputfile"):
                inputfile = arg
            elif opt in ("-r", "--release"):
                release = arg
            elif opt in ("-o", "--imagedirectory"):
                imagedir = arg.rstrip("/")
            else:
                bail("Unrecognised argument: " + opt)
    else:
        bail("Failed to read arguments")

    if not release:
        bail("Missing required argument: -r/--release")
    return 0

def yaml_parse(content):
    result = ""
    lines = content.split('\n')
    for line in lines:
        if line.strip() and not line.strip().startswith('#'):
            result += line + "\n"
    return yaml.safe_load(result)

def jsonarray(devices, vendor, name, url, extract_size, extract_sha256, image_download_size, image_download_sha256):
    if not vendor in devices:
        devices[vendor] = []

    jsondata = {"name": name,
                "description": "Kali Linux ARM image for the {}".format(name),
                "url": url,
                "icon": "https://www.kali.org/images/favicon.png",
                "release_date": datetime.datetime.today().strftime("%Y-%m-%d"),
                "extract_size": extract_size,
                "extract_sha256": extract_sha256,
                "image_download_size": "{}".format(image_download_size),
                "image_download_sha256": image_download_sha256,
                "website": "https://www.kali.org/"}
    devices[vendor].append(jsondata)
    return devices

def generate_manifest(data):
    global release, qty_devices, qty_images, qty_release_images
    default = ""
    devices = {}

    # Iterate over per input (depth 1)
    for yaml in data['devices']:
        # Iterate over vendors
        for vendor in yaml.keys():
            # @g0tmi1k: Feels like there is a cleaner way todo this
            if not vendor == "raspberrypi":
                continue
            # Ready to have a unique name in the entry
            img_seen = set()
            # Iterate over board (depth 2)
            for board in yaml[vendor]:
                qty_devices += 1
                # Iterate over per board
                for key in board.keys():
                    # Check if there is an image for the board
                    if 'images' in key:
                        # Iterate over image (depth 3)
                        for image in board[key]:
                            qty_images += 1
                            # Check that it's not EOL or community supported
                            if image.get('support') == "kali":
                                name = image.get('name', default)
                                # If we haven't seen this image before for this vendor
                                if name not in img_seen:
                                    img_seen.add(name)
                                    qty_release_images += 1

                                    filename = "kali-linux-{}-{}".format(release, image.get('image', default))

                                    # Check to make sure files got created
                                    for ext in file_ext:
                                        check_file = '{}/{}.{}'.format(imagedir, filename, ext)
                                        if not os.path.isfile(check_file):
                                            bail("Missing: '{}'".format(check_file), "Please create the image before running")

                                    with open('{}/{}.xz.sha256sum'.format(imagedir, filename)) as f:
                                        image_download_sha256 = f.read().split()[0]
                                    with open('{}/{}.sha256sum'.format(imagedir, filename)) as f:
                                        extract_sha256 = f.read().split()[0]

                                    url = "https://kali.download/arm-images/kali-{}/{}.xz".format(release, filename)

                                    # @g0tmi1k: not happy about external OS, rather keep it in python (import lzma)
                                    try:
                                        unxz = subprocess.check_output("unxz --verbose --list {}/{}.xz | grep 'Uncompressed'".format(imagedir, filename), shell=True)
                                        extract_size = re.findall(r'\((.*?) B\)', str(unxz))[0]
                                        extract_size = extract_size.replace(',', '')
                                    except subprocess.CalledProcessError as e:
                                        #print("command '{}' return with error (code {})".format(e.cmd, e.returncode))
                                        extract_size = "0"

                                   #image_download_size = os.stat('{}/{}.xz'.format(imagedir, filename)).st_size
                                    image_download_size = os.path.getsize('{}/{}.xz'.format(imagedir, filename))
                                    jsonarray(devices, 'os_list', name, url, extract_size, extract_sha256, image_download_size, image_download_sha256)
    return json.dumps(devices, indent = 2)

def createdir(dir):
    try:
        if not os.path.exists(dir):
            os.makedirs(dir)
    except:
        bail('Directory "' + dir + '" does not exist and cannot be created')
    return 0

def readfile(file):
    try:
        with open(file) as f:
            data = f.read()
            f.close()
    except:
        bail("Cannot open input file: " + file)
    return data

def writefile(data, file):
    try:
        with open(file, 'w') as f:
            f.write(str(data))
            f.close()
    except:
        bail("Cannot write to output file: " + file)
    return 0

def main(argv):
    global inputfile, imagedir, release

    # Parse command-line arguments
    if len(sys.argv) > 1:
        getargs(argv)
    else:
        bail("Missing arguments")

    # Assign variables
    manifest = imagedir + "/rpi-imager.json"
    data = readfile(inputfile)

    # Get data
    res = yaml_parse(data)
    manifest_list = generate_manifest(res)

    # Create output directory if required
    createdir(imagedir)

    # Create manifest file
    writefile(manifest_list, manifest)

    # Print result and exit
    print('\nStats:')
    print('  - Total devices\t: {}'.format(qty_devices))
    print('  - Total images\t: {}'.format(qty_images))
    print('  - {} rpi images\t: {}'.format(release, qty_release_images))
    print("\n")
    print('Manifest file created\t: {}'.format(manifest))

    exit(0)

if __name__ == "__main__":
    main(sys.argv[1:])
