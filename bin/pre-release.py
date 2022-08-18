#!/usr/bin/env python3

# NetHunter ~ https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-project/-/blob/2e26ee29/nethunter-installer/prep-release.py
# ARM Devices ~ https://gitlab.com/kalilinux/build-scripts/kali-arm/-/blob/master/devices.yml

###############################################
# Script to prepare Kali ARM quarterly release
##
# This should be run either before or after images are created.
##
# It parses the YAML sections of the devices.yml and creates:
# - "<outputdir>/manifest.json": manifest file mapping image name to display name
##
# Dependencies:
# sudo apt -y install python3 python3-yaml
##
# Usage:
# ./bin/pre-release.py -i <input file> -r <release> -o <output directory>
##
# E.g.:
# ./bin/pre-release.py -i devices.yml -r 2022.3 -o images/

import datetime
import getopt
import json
import os
import stat
import sys

import yaml  # python3 -m pip install pyyaml --user

manifest = ""     # Generated automatically (<outputdir>/manifest.json)

release = ""

outputdir = ""

inputfile = ""

qty_devices = 0
qty_images = 0
qty_release_images = 0

# Input:
# ------------------------------------------------------------
# See: ./devices.yml
# https://gitlab.com/kalilinux/build-scripts/kali-arm/-/blob/master/devices.yml


def bail(message="", strerror=""):
    outstr = ""

    prog = sys.argv[0]

    if message != "":
        outstr = "\nError: {}".format(message)

    if strerror != "":
        outstr += "\nMessage: {}\n".format(strerror)

    else:
        outstr += "\n\nUsage: {} -i <input file> -o <output directory> -r <release>".format(
            prog)
        outstr += "\nE.g. : {} -i devices.yml -o images/ -r {}.1\n".format(
            prog, datetime.datetime.now().year)

    print(outstr)

    sys.exit(2)


def getargs(argv):
    global inputfile, outputdir, release

    try:
        opts, args = getopt.getopt(
            argv, "hi:o:r:", ["inputfile=", "outputdir=", "release="])

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

            elif opt in ("-o", "--outputdirectory"):
                outputdir = arg.rstrip("/")

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


def jsonarray(devices, vendor, name, filename, preferred, slug):
    if not vendor in devices:
        devices[vendor] = []

    jsondata = {"name": name,
                "filename": filename,
                "preferred": preferred,
                "slug": slug}

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

                                    filename = "kali-linux-{}-{}".format(
                                        release, image.get('image', default))

                                    preferred = image.get(
                                        'preferred-image', default)

                                    slug = image.get('slug', default)

                                    jsonarray(devices, vendor, name,
                                              filename, preferred, slug)

    return json.dumps(devices, indent=2)


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
    global inputfile, outputdir, release

    # Parse command-line arguments
    if len(sys.argv) > 1:
        getargs(argv)

    else:
        bail("Missing arguments")

    # Assign variables
    manifest = outputdir + "/manifest.json"
    data = readfile(inputfile)

    # Get data
    res = yaml_parse(data)
    manifest_list = generate_manifest(res)

    # Create output directory if required
    createdir(outputdir)

    # Create manifest file
    writefile(manifest_list, manifest)

    # Print result and exit
    print('\nStats:')
    print('  - Total devices\t: {}'.format(qty_devices))
    print('  - Total images\t: {}'.format(qty_images))
    print('  - {} images\t: {}'.format(release, qty_release_images))
    print("\n")
    print('Manifest file created\t: {}'.format(manifest))

    exit(0)


if __name__ == "__main__":
    main(sys.argv[1:])
